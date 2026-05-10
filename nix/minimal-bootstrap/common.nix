{ lib }:

{
  mkMeta =
    {
      description,
      homepage,
      license ? lib.licenses.gpl3Plus,
      mainProgram ? null,
      platforms ? lib.platforms.unix,
    }:
    {
      inherit
        description
        homepage
        license
        platforms
        ;
      teams = [ lib.teams.minimal-bootstrap ];
    }
    // lib.optionalAttrs (mainProgram != null) { inherit mainProgram; };

  mkVersionTest =
    bash: pname: version: program: result:
    bash.runCommand "${pname}-get-version-${version}" { } ''
      ${result}/bin/${program} --version
      mkdir $out
    '';
}
