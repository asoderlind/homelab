{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Proton VPN split tunnel for Transmission - and only Transmission. The
  # "protonvpn" network namespace's sole default route is the WireGuard
  # tunnel; transmission.service is attached to it (see transmission.nix),
  # while everything else on the host (Tailscale, ACME, restic, Nextcloud)
  # keeps using the normal uplink. This doubles as a kill switch: tunnel
  # down means the namespace has no egress at all.

  # WireGuard private key from the config generated at account.protonvpn.com
  # (Downloads -> WireGuard configuration, P2P server, NAT-PMP enabled).
  age.secrets.protonvpn-wg-key.file = ../../../secrets/protonvpn-wg-key.age;

  # Namespace + veth plumbing. The veth pair exists only so nginx on the
  # host can reach the RPC port inside the namespace; it carries no default
  # route, so it is not a leak path for peer traffic.
  systemd.services.protonvpn-netns = {
    description = "Network namespace for Proton VPN split tunnel";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      [ -e /run/netns/protonvpn ] || ip netns add protonvpn
      ip -n protonvpn link set lo up
      if ! ip link show veth-trans >/dev/null 2>&1; then
        ip link add veth-trans type veth peer name veth-trans-ns
        ip link set veth-trans-ns netns protonvpn
      fi
      ip addr replace 10.233.0.1/24 dev veth-trans
      ip link set veth-trans up
      ip -n protonvpn addr replace 10.233.0.2/24 dev veth-trans-ns
      ip -n protonvpn link set veth-trans-ns up
    '';
  };

  # The wg link is created in the init namespace (so its encrypted UDP
  # socket egresses via the normal uplink) and then moved into the netns;
  # allowedIPs 0.0.0.0/0 becomes the namespace's default route.
  networking.wireguard.interfaces.protonvpn = {
    interfaceNamespace = "protonvpn";
    # [Interface] Address from the generated config - the tunnel-internal
    # address, not the server's public IP.
    ips = [ "10.2.0.2/32" ];
    privateKeyFile = config.age.secrets.protonvpn-wg-key.path;
    peers = [
      {
        name = "proton-p2p";
        publicKey = "oU38B513VDJGkoIpyMEVmP26F5OtmmxL3TBU8EmeCDo=";
        endpoint = "169.150.208.158:51820";
        allowedIPs = [ "0.0.0.0/0" ];
        persistentKeepalive = 25;
      }
    ];
  };
  systemd.services.wireguard-protonvpn = {
    requires = [ "protonvpn-netns.service" ];
    after = [ "protonvpn-netns.service" ];
  };

  # 10.2.0.1 is Proton's in-tunnel resolver (same for every Proton WG
  # config). `ip netns exec protonvpn` picks this up automatically;
  # transmission.service gets it via an explicit bind mount because
  # systemd's NetworkNamespacePath= does not do iproute2's /etc/netns
  # resolv.conf swap.
  environment.etc."netns/protonvpn/resolv.conf".text = "nameserver 10.2.0.1\n";

  # Proton's NAT-PMP port forwarding (paid plan): mappings expire after 60s,
  # so renew both protocols continuously and tell Transmission whenever the
  # assigned public port changes. Follows transmission's lifecycle.
  systemd.services.protonvpn-natpmp = {
    description = "Proton VPN NAT-PMP port forwarding for Transmission";
    wantedBy = [ "transmission.service" ];
    bindsTo = [ "transmission.service" ];
    after = [ "transmission.service" ];
    path = [
      pkgs.libnatpmp
      config.services.transmission.package
    ];
    serviceConfig = {
      Restart = "always";
      RestartSec = 10;
      NetworkNamespacePath = "/run/netns/protonvpn";
    };
    script = ''
      lastport=""
      while true; do
        natpmpc -a 1 0 udp 60 -g 10.2.0.1 >/dev/null || echo "natpmpc udp renewal failed" >&2
        out=$(natpmpc -a 1 0 tcp 60 -g 10.2.0.1) || { echo "natpmpc tcp renewal failed" >&2; sleep 10; continue; }
        port=$(echo "$out" | grep -oE 'Mapped public port [0-9]+' | grep -oE '[0-9]+' | head -1)
        if [ -n "$port" ] && [ "$port" != "$lastport" ]; then
          if transmission-remote 127.0.0.1:9091 --port "$port" >/dev/null; then
            echo "forwarded port changed, transmission peer port set to $port"
            lastport=$port
          fi
        fi
        sleep 45
      done
    '';
  };
}
