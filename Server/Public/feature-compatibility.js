export const supportedWriteFeatures=['elementTypography','productionBaselines','dualDialogue','scriptAnnotations'];
export function requiredWriteFeatures(document){const p=document.project||document,features=[];
 if(Object.keys(p.frontstageScriptLayout?.elements||{}).length||Object.keys(p.frontstageScriptLayout?.frontstageInactiveElementTypography||{}).length)features.push('elementTypography');
 if(p.productionRevision||p.productionRevisionHistory?.length)features.push('productionBaselines');
 const html=[...(p.beats||[]).map(s=>s.content||''),...(p.frontstageWhiteboard?.beats||[]).map(b=>b.html||''),...(p.frontstagePullouts||[]).map(e=>e.beat?.html||'')];
 if(html.some(s=>s.includes('data-dot-'))||(p.beats||[]).some(s=>s.frontstageHeadingMarkup?.includes('data-dot-')))features.push('scriptAnnotations');
 if(html.some(s=>s.includes('sc-dual-')||s.includes('data-dual-pair')))features.push('dualDialogue');return features;
}
export function validateServerFeatures(document,supported=[]){const missing=requiredWriteFeatures(document).filter(feature=>!supported.includes(feature));if(missing.length)throw Error('Update the DOT shared server before syncing this project. Local changes remain saved. Missing support: '+missing.join(', '));}
