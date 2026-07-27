# Agenix key configuration - defines which keys can decrypt which secrets
# To get the Dell server's host key, run on the server:
#   cat /etc/ssh/ssh_host_ed25519_key.pub
let
  # Dell server host key (replace with actual key from server)
  dell = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFJPq/e8eKJNreORcH237atCR17bxVm+YPu4Zk11aZxa root@nixos-homelab-dell";
  # Personal key (~/.ssh/id_ed25519) so secrets can be created/edited from
  # the laptop without needing the server's host key.
  axel = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIjaiim8xgFT9uZkzEyvOwx3ZNMs5e37/ZSiN8ZdN25 axesode@gmail.com";
in
{
  "grafana-secret-key.age".publicKeys = [
    dell
    axel
  ];
  # TELEGRAM_BOT_TOKEN=... env file for alertmanager's telegram receiver
  "alertmanager-env.age".publicKeys = [
    dell
    axel
  ];
  # CLOUDFLARE_DNS_API_TOKEN=... env file for ACME DNS-01 challenges
  "acme-cloudflare-env.age".publicKeys = [
    dell
    axel
  ];
  # Nextcloud admin account password (services.nextcloud.config.adminpassFile)
  "nextcloud-admin-pass.age".publicKeys = [
    dell
    axel
  ];
  # Random token for the serverinfo app, read by the prometheus nextcloud exporter
  "nextcloud-serverinfo-token.age".publicKeys = [
    dell
    axel
  ];
  # Restic repository encryption password, shared by the local and off-site
  # repos. Keep an off-host copy in the password manager - neither repo is
  # readable without it.
  "restic-password.age".publicKeys = [
    dell
    axel
  ];
  # AWS_ACCESS_KEY_ID=... / AWS_SECRET_ACCESS_KEY=... env file for the
  # off-site repo in Hetzner Object Storage
  "restic-offsite-env.age".publicKeys = [
    dell
    axel
  ];
  # WireGuard private key from the Proton VPN config generated at
  # account.protonvpn.com (key only, one line)
  "protonvpn-wg-key.age".publicKeys = [
    dell
    axel
  ];
  # Kavita JWT signing key (services.kavita.tokenKeyFile), 64 random bytes
  # base64-encoded. Losing it only invalidates active sessions.
  "kavita-token.age".publicKeys = [
    dell
    axel
  ];
}
