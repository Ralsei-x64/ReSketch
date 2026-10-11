{
  description = "ReSketch, a Qt and Kirigami desktop client for Figma";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          kde = pkgs.kdePackages;
        in
        {
          default = self.packages.${system}.resketch;
          resketch = pkgs.stdenv.mkDerivation {
            pname = "resketch";
            version = "0.1.0";
            src = pkgs.lib.cleanSource self;

            nativeBuildInputs = [ pkgs.cmake pkgs.ninja kde.wrapQtAppsHook ];
            buildInputs = [
              kde.qtbase
              kde.qtdeclarative
              kde.qtwebengine
              kde.kwindowsystem
              kde.kcolorscheme
              kde.kiconthemes
              kde.kirigami
              kde.qqc2-desktop-style
              kde.breeze
              kde.breeze-icons
            ];
            cmakeFlags = [ "-DBUILD_TESTING=ON" ];
            doCheck = true;
            preCheck = ''
              export QT_PLUGIN_PATH=
              export QML2_IMPORT_PATH=
              export XDG_CACHE_HOME="$TMPDIR/resketch-cache"
              export XDG_CONFIG_HOME="$TMPDIR/resketch-config"
              export XDG_DATA_HOME="$TMPDIR/resketch-data"
              export XDG_RUNTIME_DIR="$TMPDIR/resketch-runtime"
              mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
              mkdir -m 700 -p "$XDG_RUNTIME_DIR"
              for qtPath in "''${qtHostPathSeen[@]}"; do
                addToSearchPath QT_PLUGIN_PATH "$qtPath/$qtPluginPrefix"
                addToSearchPath QML2_IMPORT_PATH "$qtPath/$qtQmlPrefix"
                addToSearchPath XDG_DATA_DIRS "$qtPath/share"
              done
            '';

            meta = {
              description = "Qt and Kirigami desktop client for Figma";
              mainProgram = "resketch";
              platforms = systems;
            };
          };
        });

      apps = forAllSystems (system: {
        default = self.apps.${system}.resketch;
        resketch = {
          type = "app";
          program = "${self.packages.${system}.resketch}/bin/resketch";
          meta.description = "Launch ReSketch";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.resketch ];
            packages = [ pkgs.pkg-config pkgs.nodejs ];
            shellHook = ''
              # Include the transitive Qt/KDE modules discovered by the wrapping hook.
              # Use this flake's Qt version instead of inherited system module paths.
              export QT_PLUGIN_PATH=
              export QML2_IMPORT_PATH=
              for qtPath in "''${qtHostPathSeen[@]}"; do
                addToSearchPath QT_PLUGIN_PATH "$qtPath/$qtPluginPrefix"
                addToSearchPath QML2_IMPORT_PATH "$qtPath/$qtQmlPrefix"
                addToSearchPath XDG_DATA_DIRS "$qtPath/share"
              done
              unset qtPath
            '';
          };
        });

      checks = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          resketch = self.packages.${system}.resketch;
          javascript = pkgs.runCommand "resketch-javascript-tests" {
            nativeBuildInputs = [ pkgs.nodejs ];
          } ''
            cd ${self}
            for test in tests/*.test.js; do
              node "$test"
            done
            touch "$out"
          '';
        });
    };
}
