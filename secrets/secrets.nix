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
}
