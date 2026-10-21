// Paginate actual browser text measurements without dropping oversized paragraphs or inline styles.
export function paginateParagraphs(makePage, nodes, height) {
  let page=makePage();
  const keepNext=n=>n?.matches?.('.sc-slugline,.sc-character,.sc-parenthetical');
  const rangeAt=(node,offset)=>{const range=document.createRange(),walker=document.createTreeWalker(node,NodeFilter.SHOW_TEXT);let text;while((text=walker.nextNode())){if(offset<=text.length){range.setStart(text,offset);return range;}offset-=text.length;}range.selectNodeContents(node);range.collapse(false);return range;};
  const split=(node,offset)=>{const point=rangeAt(node,offset),a=document.createRange(),b=document.createRange();a.selectNodeContents(node);a.setEnd(point.startContainer,point.startOffset);b.selectNodeContents(node);b.setStart(point.startContainer,point.startOffset);const first=node.cloneNode(false),last=node.cloneNode(false);first.append(a.cloneContents());last.append(b.cloneContents());return[first,last];};
  for(const entry of nodes){
    if(entry.newPage&&page.childElementCount)page=makePage();
    let node=entry.node;page.append(node);
    if(page.scrollHeight>height+1&&page.childElementCount>1){node.remove();let kept=[];while(keepNext(page.lastElementChild)){const last=page.lastElementChild;last.remove();kept.unshift(last);}if(page.childElementCount)page=makePage();page.append(...kept,node);}
    while(page.scrollHeight>height+1&&node.textContent.length>1){
      const original=node,text=original.textContent;let low=1,high=text.length-1,best=0;
      while(low<=high){const mid=Math.floor((low+high)/2);const[candidate]=split(original,mid);node.replaceWith(candidate);node=candidate;if(page.scrollHeight<=height+1){best=mid;low=mid+1;}else high=mid-1;}
      if(!best){node.replaceWith(original);node=original;if(page.childElementCount>1){node.remove();page=makePage();page.append(node);continue;}break;}
      // Prefer word boundaries; retain every character in one of the two fragments.
      if(/[\uDC00-\uDFFF]/.test(text[best]))best=Math.max(2,best-1);
      const space=text.lastIndexOf(' ',best);if(space>best*.7)best=space+1;
      const[first,last]=split(original,best);node.replaceWith(first);page=makePage();page.append(last);node=last;
    }
  }
}
