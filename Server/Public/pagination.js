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
    if(node.matches?.('.sc-dual-group')){
      let iterations=0;
      while(page.scrollHeight>height+1&&node.textContent.length>1){
        if(++iterations>10000)throw Error('Dual dialogue could not be paginated.');
        const available=height-(node.getBoundingClientRect().top-page.getBoundingClientRect().top)-20;
        const rest=node.cloneNode(false);let moved=false;
        for(const column of [...node.children]){
          const tail=column.cloneNode(false),paragraphs=[...column.children],cue=paragraphs.find(p=>p.matches('.sc-character'));
          const fits=()=>column.getBoundingClientRect().height<=available+1;
          if(!fits()){
            let cut=paragraphs.length-1;
            while(cut>=0){const p=paragraphs[cut];p.remove();tail.prepend(p);if(fits())break;cut--;}
            const overflow=tail.firstElementChild;
            if(overflow&&!keepNext(overflow)&&overflow.textContent.length>1){
              overflow.remove();column.append(overflow);let candidate=overflow,low=1,high=overflow.textContent.length-1,best=0;
              while(low<=high){const mid=Math.floor((low+high)/2),[head]=split(overflow,mid);candidate.replaceWith(head);candidate=head;if(fits()){best=mid;low=mid+1;}else high=mid-1;}
              if(best){const value=overflow.textContent;if(/[\uDC00-\uDFFF]/.test(value[best]))best=Math.max(1,best-1);const space=value.lastIndexOf(' ',best);if(space>best*.7)best=space+1;const[head,last]=split(overflow,best);candidate.replaceWith(head);tail.prepend(last);}
              else{candidate.remove();tail.prepend(overflow);}
            }
            // Keep an ending cue/parenthetical with its dialogue on the next page.
            while(keepNext(column.lastElementChild)){const p=column.lastElementChild;p.remove();tail.prepend(p);}
            if(tail.children.length){
              moved=true;
              if(cue&&!tail.firstElementChild.matches('.sc-character')){const continuation=cue.cloneNode(true);continuation.dataset.pageContinuation='true';continuation.textContent=cue.textContent.replace(/\s*\(CONT['’]?D\)\s*$/i,'')+" (CONT'D)";tail.prepend(continuation);}
              if(column.children.length){const more=document.createElement('p');more.className='sc-dual-more';more.dataset.pageContinuation='true';more.textContent='(MORE)';column.append(more);}
            }
          }
          rest.append(tail);
        }
        if(!moved)break;
        page=makePage();page.append(rest);node=rest;
      }
      continue;
    }
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
