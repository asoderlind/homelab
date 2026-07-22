# Agenix key configuration - defines which keys can decrypt which secrets
# To get the Dell server's host key, run on the server:
#   cat /etc/ssh/ssh_host_ed25519_key.pub
let
  # Dell server host key (replace with actual key from server)
  dell = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFJPq/e8eKJNreORcH237atCR17bxVm+YPu4Zk11aZxa root@nixos-homelab-dell";
in
{
  "grafana-secret-key.age".publicKeys = [ dell ];
}
