{ pkgs, lib }:

{ file, identity }:

{
  name = "age-decrypt";
  deps = [ pkgs.age ];
  
  bash = ''
    echo "→ Decrypting secrets with age"
    
    # Decrypt and export as env vars
    eval $(${pkgs.age}/bin/age -d -i ${toString identity} ${toString file})
    
    echo "✓ Secrets decrypted"
  '';
}
