// UI wordmarks follow their surface. Installation icons follow system appearance.
const systemAppearance=matchMedia('(prefers-color-scheme: dark)');
function refreshBrand(){
  const theme=systemAppearance.matches?'dark':'light';
  const manifest=document.querySelector('link[rel="manifest"]');
  if(manifest)manifest.href='/manifest-'+theme+'.json';
}
refreshBrand();
systemAppearance.addEventListener('change',refreshBrand);
