{
  config,
  lib,
  pkgs,
  ...
}:

{
  users.users.axel = {
    isNormalUser = true;
    description = "axel";
    # Pinned (matches the account already on disk - see filesystems.nix)
    # so oci-containers can resolve /run/user/1000 for rootless Podman's
    # RequiresMountsFor at eval time instead of an unresolved UID.
    uid = 1000;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    # Declared in-repo so a rebuild can never lock out key-based SSH
    # (deploy-rs connects with ~/.ssh/homelab/dell).
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDFdhR10TbS6Yap18mcLQjIb9F2LRpgjM2fQIpuzar7pncP4q7y82wsSY7et36IDdeQxVXfh/LNlaIr5s+W2sxbgvKL6E9an35sn8qDLGJ04oGJS1Yc4M+0UY4ZQ0DSWTV/Z9Bykb83JRmgUMyBvqZFqjzz/f7eX7jsd2MjJ05iAAPatu4jRYMPx0sJlUFwxR9x0Ylnz351KxyEKGDa0W72257FaFVjT6AX6qjp19NQehJsqQVHAY1KT9mU7ZaEvvBbs59E2AYcQOJ3oiWgAPxmmyQwymD7gzVtwrYkuMPVgfZblgVcQj6jCX9BehO7SkNx/ydKMjmSSuVq31zZwRo+BAdQEz1k71u08/SHx7xbkhIX0aIBwIn21UFmi9pgoKf0yNtaqGl8MBIKSHCcazdppuyP/N7Iira15FxlpY7LhHQZ1IdmWNpsZXkglIkcmaaQwfvaUYK06GSOLJYRpCdHy5Kbdk2t9iv7Vibyyy216r/cfug6tnPmHLbFERa1OW8= axel@Axels-macbook.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIjaiim8xgFT9uZkzEyvOwx3ZNMs5e37/ZSiN8ZdN25 axesode@gmail.com"
    ];
    packages = with pkgs; [ ];
    # Rootless Podman containers run as axel via a system unit
    # (virtualisation.oci-containers' `podman.user`); lingering keeps
    # /run/user/1000 available at boot so that unit doesn't race an
    # interactive login.
    linger = true;
  };
}
