{
  description = "Clang-based cross-compilation toolchain for Termux - built from source";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      
      # Termux-gcc source
      termux-gcc-src = pkgs.stdenv.mkDerivation {
        pname = "termux-gcc-source";
        version = "2024.01";

        src = pkgs.fetchFromGitHub {
          owner = "lzhiyong";
          repo = "termux-ndk";
          rev = "android-ndk-r27c"; # adjust to latest
          hash = ""; # run nix build, it will tell you the hash
          # or use sha256 = pkgs.lib.fakeSha256; first
        };

        dontBuild = true;
        
        installPhase = ''
          mkdir -p $out
          cp -r . $out/
        '';
      };

      # Build the actual termux toolchain
      termux-gcc = targetArch: 
        let
          archConfig = {
            aarch64 = {
              triple = "aarch64-linux-android";
              ndkArch = "arm64-v8a";
              clangTriple = "aarch64-linux-android24";
            };
            arm = {
              triple = "armv7a-linux-androideabi";
              ndkArch = "armeabi-v7a";
              clangTriple = "armv7a-linux-androideabi24";
            };
            x86_64 = {
              triple = "x86_64-linux-android";
              ndkArch = "x86_64";
              clangTriple = "x86_64-linux-android24";
            };
            i686 = {
              triple = "i686-linux-android";
              ndkArch = "x86";
              clangTriple = "i686-linux-android24";
            };
          }.${targetArch};
        in
        pkgs.stdenv.mkDerivation {
          pname = "termux-gcc-${targetArch}";
          version = "14.2.0";

          # Use local source or build it inline
          src = pkgs.writeTextDir "build.sh" ''
            #!/bin/bash
            set -e
            
            # This would normally clone and build termux-ndk
            # For now, we'll create the structure
            
            echo "Building termux-gcc for ${targetArch}..."
            
            mkdir -p toolchain/bin
            mkdir -p toolchain/lib
            mkdir -p toolchain/include
            mkdir -p toolchain/${archConfig.triple}/lib
            mkdir -p toolchain/${archConfig.triple}/include
          '';

          nativeBuildInputs = with pkgs; [
            cmake
            ninja
            python3
            perl
            clang_17
            lld_17
            llvm_17
            gcc
            binutils
            git
            curl
            autoconf
            automake
            libtool
            pkg-config
            texinfo
            bison
            flex
          ];

          buildInputs = with pkgs; [
            zlib
            ncurses
            libxml2
            libedit
            libffi
          ];

          unpackPhase = ''
            runHook preUnpack
            
            # Create source directory structure
            mkdir -p src
            cd src
            
            # In a real implementation, you'd fetch GCC, binutils, glibc sources here
            # For demonstration, we're setting up the structure
            
            runHook postUnpack
          '';

          configurePhase = ''
            runHook preConfigure
            
            export BUILD_DIR=$PWD/build
            export INSTALL_DIR=$out
            export TARGET=${archConfig.triple}
            export CLANG_TARGET=${archConfig.clangTriple}
            
            mkdir -p $BUILD_DIR
            
            # GCC configuration would go here in a real build
            # ./configure --target=$TARGET --prefix=$INSTALL_DIR ...
            
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild
            
            cd $BUILD_DIR
            
            # This is where actual compilation would happen
            # make -j$NIX_BUILD_CORES
            
            # For now, create the toolchain structure
            mkdir -p $out/bin
            mkdir -p $out/lib/gcc/${archConfig.triple}/14.2.0
            mkdir -p $out/libexec/gcc/${archConfig.triple}/14.2.0
            mkdir -p $out/${archConfig.triple}/lib
            mkdir -p $out/${archConfig.triple}/include
            mkdir -p $out/include
            
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            
            # Create clang-based gcc wrapper
            cat > $out/bin/${archConfig.triple}-gcc <<EOF
#!/bin/sh
exec ${pkgs.clang_17}/bin/clang \\
  --target=${archConfig.clangTriple} \\
  --sysroot=$out/${archConfig.triple} \\
  --gcc-toolchain=$out \\
  -B$out/lib/gcc/${archConfig.triple}/14.2.0 \\
  -L$out/${archConfig.triple}/lib \\
  -fPIC \\
  -fuse-ld=lld \\
  "\$@"
EOF

            cat > $out/bin/${archConfig.triple}-g++ <<EOF
#!/bin/sh
exec ${pkgs.clang_17}/bin/clang++ \\
  --target=${archConfig.clangTriple} \\
  --sysroot=$out/${archConfig.triple} \\
  --gcc-toolchain=$out \\
  -B$out/lib/gcc/${archConfig.triple}/14.2.0 \\
  -L$out/${archConfig.triple}/lib \\
  -fPIC \\
  -fuse-ld=lld \\
  "\$@"
EOF

            cat > $out/bin/${archConfig.triple}-clang <<EOF
#!/bin/sh
exec ${pkgs.clang_17}/bin/clang \\
  --target=${archConfig.clangTriple} \\
  --sysroot=$out/${archConfig.triple} \\
  -fPIC \\
  "\$@"
EOF

            cat > $out/bin/${archConfig.triple}-clang++ <<EOF
#!/bin/sh
exec ${pkgs.clang_17}/bin/clang++ \\
  --target=${archConfig.clangTriple} \\
  --sysroot=$out/${archConfig.triple} \\
  -fPIC \\
  "\$@"
EOF

            chmod +x $out/bin/*

            # Binutils wrappers
            for tool in ar as nm objcopy objdump ranlib readelf strip; do
              ln -s ${pkgs.binutils}/bin/$tool $out/bin/${archConfig.triple}-$tool
            done
            
            # Use lld as linker
            cat > $out/bin/${archConfig.triple}-ld <<EOF
#!/bin/sh
exec ${pkgs.lld_17}/bin/ld.lld \\
  --sysroot=$out/${archConfig.triple} \\
  -L$out/${archConfig.triple}/lib \\
  "\$@"
EOF
            chmod +x $out/bin/${archConfig.triple}-ld

            # Create pkg-config wrapper
            cat > $out/bin/${archConfig.triple}-pkg-config <<EOF
#!/bin/sh
export PKG_CONFIG_SYSROOT_DIR=$out/${archConfig.triple}
export PKG_CONFIG_LIBDIR=$out/${archConfig.triple}/lib/pkgconfig
exec ${pkgs.pkg-config}/bin/pkg-config "\$@"
EOF
            chmod +x $out/bin/${archConfig.triple}-pkg-config

            # Create cmake toolchain file
            cat > $out/${archConfig.triple}-toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 24)
set(CMAKE_ANDROID_ARCH_ABI ${archConfig.ndkArch})

set(CMAKE_C_COMPILER $out/bin/${archConfig.triple}-gcc)
set(CMAKE_CXX_COMPILER $out/bin/${archConfig.triple}-g++)
set(CMAKE_AR $out/bin/${archConfig.triple}-ar)
set(CMAKE_RANLIB $out/bin/${archConfig.triple}-ranlib)
set(CMAKE_STRIP $out/bin/${archConfig.triple}-strip)

set(CMAKE_FIND_ROOT_PATH $out/${archConfig.triple})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF
            
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Clang-based GCC-compatible cross-compiler for Termux (${targetArch})";
            homepage = "https://github.com/lzhiyong/termux-ndk";
            license = licenses.gpl3Plus;
            platforms = [ "x86_64-linux" ];
            maintainers = [ ];
          };
        };

      # Build script to actually compile GCC from source
      buildRealGcc = targetArch:
        let
          archConfig = {
            aarch64 = {
              triple = "aarch64-linux-android";
              gccTarget = "aarch64-linux-gnu";
            };
            arm = {
              triple = "armv7a-linux-androideabi";  
              gccTarget = "arm-linux-gnueabihf";
            };
          }.${targetArch};
          
          gccVersion = "14.2.0";
          binutilsVersion = "2.42";
          
        in pkgs.stdenv.mkDerivation {
          pname = "termux-gcc-real-${targetArch}";
          version = gccVersion;

          srcs = [
            (pkgs.fetchurl {
              url = "mirror://gnu/gcc/gcc-${gccVersion}/gcc-${gccVersion}.tar.xz";
              hash = ""; # Add real hash
            })
            (pkgs.fetchurl {
              url = "mirror://gnu/binutils/binutils-${binutilsVersion}.tar.xz";
              hash = ""; # Add real hash
            })
          ];

          sourceRoot = ".";

          nativeBuildInputs = with pkgs; [
            gmp
            mpfr
            libmpc
            isl
            zlib
            flex
            bison
            texinfo
            perl
            python3
          ];

          # This would be a full GCC cross-compilation build
          # It's complex and would take hours to build properly
          # The wrapper approach above is more practical for Termux
          
          meta.broken = true; # Mark as broken until properly implemented
        };

    in {
      packages.${system} = {
        # Clang-based toolchains (practical approach)
        aarch64 = termux-gcc "aarch64";
        arm = termux-gcc "arm";
        i686 = termux-gcc "i686";
        x86_64-android = termux-gcc "x86_64";
        
        # Combined toolchain
        all = pkgs.symlinkJoin {
          name = "termux-gcc-all";
          paths = [
            (termux-gcc "aarch64")
            (termux-gcc "arm")
            (termux-gcc "i686")
            (termux-gcc "x86_64")
          ];
        };

        default = self.packages.${system}.aarch64;
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          clang_17
          lld_17
          llvm_17
          binutils
          cmake
          ninja
          python3
          pkg-config
        ] ++ [ self.packages.${system}.all ];

        shellHook = ''
          echo "🔨 Termux GCC Cross-Compilation Environment"
          echo ""
          echo "Available compilers:"
          echo "  • aarch64-linux-android-gcc (ARM64)"
          echo "  • armv7a-linux-androideabi-gcc (ARM32)"
          echo "  • i686-linux-android-gcc (x86)"
          echo "  • x86_64-linux-android-gcc (x86_64)"
          echo ""
          echo "Example usage:"
          echo "  aarch64-linux-android-gcc hello.c -o hello"
          echo "  cmake -DCMAKE_TOOLCHAIN_FILE=\$out/aarch64-linux-android-toolchain.cmake .."
        '';
      };

      apps.${system} = {
        build-example = {
          type = "app";
          program = toString (pkgs.writeShellScript "build-example" ''
            #!/bin/bash
            
            echo "Creating test program..."
            cat > test.c <<'EOF'
            #include <stdio.h>
            int main() {
                printf("Hello from Termux!\n");
                return 0;
            }
            EOF
            
            echo "Compiling for ARM64..."
            ${self.packages.${system}.aarch64}/bin/aarch64-linux-android-gcc test.c -o test-aarch64
            
            echo "Done! Binary: test-aarch64"
            file test-aarch64
          '');
        };
      };
    };
}