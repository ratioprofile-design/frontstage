// Filename branding is separate from the stable project envelope and storage IDs.
export function parseProjectFile(text, filename='') {
  let value;
  try { value=JSON.parse(text); } catch(error) {
    if(/\.dot$/i.test(filename))throw Error('This .dot file is not a DOT project. Word templates are not supported.');
    throw error;
  }
  if(/\.dot$/i.test(filename)&&(value?.format!=='frontstage'||!value.project||typeof value.project!=='object'||Array.isArray(value.project)))
    throw Error('This .dot file is not a DOT project. Word templates are not supported.');
  return value;
}
export function projectFilename(name){return (name||'Story').replace(/[\\/]/g,'-')+'.dot';}
