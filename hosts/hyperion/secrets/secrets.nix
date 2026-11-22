let
  hyperion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKx6xOZPF4StF9diJeCVaS4Le+M7qUZiIkf9+WyT3XaJ root@nixos";
  axel = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIjaiim8xgFT9uZkzEyvOwx3ZNMs5e37/ZSiN8ZdN25 axel@soderlind.dev";
in
{
  # CLOUDFLARE_DNS_API_TOKEN=... with Zone.DNS edit access to
  # soderlind.dev, used only for ACME DNS-01 validation.
  "acme-cloudflare-env.age".publicKeys = [
    hyperion
    axel
  ];
}
