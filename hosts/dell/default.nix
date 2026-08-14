{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common
    ./filesystems.nix
    ./hardware.nix
    ./services
    ./system.nix
    ./virtualisation.nix
  ];

  networking.hostName = "nixos-homelab-dell";
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  users.users.axel = {
    # deploy-rs connects with ~/.ssh/homelab/dell.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDFdhR10TbS6Yap18mcLQjIb9F2LRpgjM2fQIpuzar7pncP4q7y82wsSY7et36IDdeQxVXfh/LNlaIr5s+W2sxbgvKL6E9an35sn8qDLGJ04oGJS1Yc4M+0UY4ZQ0DSWTV/Z9Bykb83JRmgUMyBvqZFqjzz/f7eX7jsd2MjJ05iAAPatu4jRYMPx0sJlUFwxR9x0Ylnz351KxyEKGDa0W72257FaFVjT6AX6qjp19NQehJsqQVHAY1KT9mU7ZaEvvBbs59E2AYcQOJ3oiWgAPxmmyQwymD7gzVtwrYkuMPVgfZblgVcQj6jCX9BehO7SkNx/ydKMjmSSuVq31zZwRo+BAdQEz1k71u08/SHx7xbkhIX0aIBwIn21UFmi9pgoKf0yNtaqGl8MBIKSHCcazdppuyP/N7Iira15FxlpY7LhHQZ1IdmWNpsZXkglIkcmaaQwfvaUYK06GSOLJYRpCdHy5Kbdk2t9iv7Vibyyy216r/cfug6tnPmHLbFERa1OW8= axel@Axels-macbook.local"
    ];
    # Rootless Podman system units need /run/user/1000 before login.
    linger = true;
  };
}
