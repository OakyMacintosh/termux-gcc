{
  description = "termux-gcc flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.myHostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
       # ./configuration.nix
        {
          environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            gcc
            autotools
            libtool
            zsh
            gnumake
          ];
          androidApiLevel = "30";
          androidNdkPackages = nixpkgs.legacyPackages.x86_64-linux."androidndkPkgs_${androidApiLevel}";
        pkgsCross = nixpkgs.legacyPackages.x86_64-linux.pkgsCross;
        aarch64Toolchain = androidNdkPackages.aarch64.toolchain;
        armv7aToolchain = androidNdkPackages.armv7a.toolchain;
    
  in {

   # packages.x86_64-linux.hello = nixpkgs.legacyPackages.x86_64-linux.hello;

  #  packages.x86_64-linux.default = self.packages.x86_64-linux.hello
    packages.x86_64-linux.android-aarch64-toolchain = aarch64Toolchain;

    packages.x86_64-linux.android-armv7a-toolchain = armv7aToolchain;
    
    }
        }
      ];
    };
  };
}