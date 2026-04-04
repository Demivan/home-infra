{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              opentofu
              talosctl
              kubectl
              kubernetes-helm
              kustomize
              cilium-cli
              argocd
              velero
              rustic
              hcloud
              gh
              # backblaze-b2  # TODO: broken in nixpkgs, add back for operations plan
              jq
              yq-go
            ];

            shellHook = ''
              echo "Homelab infra shell ready"
            '';
          };
        });
    };
}
