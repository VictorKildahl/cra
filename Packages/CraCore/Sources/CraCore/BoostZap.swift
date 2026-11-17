import Foundation

/// Arc's Zap (Arc 1.172.2, measured in Victor's Arc on 12 Nov 2026; docs/arc-parity.md "Zap,
/// measured"). Zap on: the page shrinks for a 58 pt shelf under it, and the element under the
/// pointer takes a yellow highlight. A click asks first, in a popover under the element: "Zap this",
/// "Zap all related elements" or "Cancel", over a footer with the selector and how many elements it
/// matches. Each zap becomes a 38 pt cell on the shelf; a click on a cell unzaps it, and while the
/// pointer is on one the page dims and the hint reads "Restore <selector>". "Done" ends Zap.
///
/// "Zap all related elements" is a slider (Arc 1.172.2 on Hacker News, 17 Nov 2026, #478): the
/// pointer across it steps through candidate selectors, fewest matches first (1, 2, 5, 19, 30, 59,
/// 88, 89 for a story title), in equal slices of its width. An orange fill follows the pointer over a
/// grey track, every match takes the highlight, the footer shows the count and selector, and a click
/// zaps that selector. Cra finds its candidates its own way (`script`'s `cands`): the element's
/// readable terms (tag, classes and ids that aren't generated, role, aria-label, data-testid, place
/// among its siblings) alone
/// and under up to four ancestors' terms, one selector per match count up to 100, never one that
/// matches inside the element or needs an escape.
public enum BoostZap {
    // MARK: The shelf (points)

    public static let shelfHeight = 58.0
    public static let cellSide = 38.0
    /// The cells, the hint and Done sit this far in from the shelf's edges.
    public static let inset = 10.0
    public static let cellGap = 8.0
    public static let cellCornerRadius = 9.0
    public static let glyphSize = 13.5
    /// "← Click to unzap": the arrow starts this far past the last cell.
    public static let unzapHintGap = 21.5
    /// The "Restore …" pill: this far past the last cell, 28.5 pt tall, a capsule.
    public static let restorePillGap = 3.0
    public static let restorePillHeight = 28.5
    public static let doneSize = (width: 58.5, height: 38.0)

    /// What the shelf says next to its cells.
    public enum Hint: Equatable, Sendable {
        /// Nothing zapped yet: "Click elements on the page to **Zap** them", centred between the
        /// shelf's left inset and Done.
        case instructions
        /// "← Click to unzap", after the cells.
        case clickToUnzap
        /// The pointer is on a cell: "**Restore** <selector>" in a pill after the cells.
        case restore(String)
    }

    public static func hint(zapped: [String], hovered: Int?) -> Hint {
        if let hovered, zapped.indices.contains(hovered) { return .restore(zapped[hovered]) }
        return zapped.isEmpty ? .instructions : .clickToUnzap
    }

    /// The x of cell `index` from the shelf's left edge.
    public static func cellX(_ index: Int) -> Double { inset * 2 + Double(index) * (cellSide + cellGap) }

    /// Where the hint starts: past the last cell (the instructions centre themselves instead).
    public static func hintX(cells: Int, pill: Bool) -> Double {
        let end = cells == 0 ? inset * 2 : cellX(cells - 1) + cellSide
        return end + (pill ? restorePillGap : unzapHintGap)
    }

    // MARK: The confirm popover

    public static let zapThis = "Zap this"
    public static let zapRelated = "Zap all related elements"
    public static let cancel = "Cancel"

    // MARK: Colours (sRGB 0–255; the theme's own come from the space)

    /// The highlight multiplies the element by this yellow; its 1 pt border is the yellow at 80 %.
    public static let highlight = (r: 247, g: 206, b: 70)
    public static let highlightBorderAlpha = 0.8
    /// The page under a hovered cell: black at 36 % (36 → 23 grey).
    public static let dimAlpha = 0.36
    public static let popoverTop = (r: 248, g: 249, b: 253)
    public static let popoverBottom = (r: 241, g: 242, b: 246)
    public static let popoverFooter = (r: 233, g: 233, b: 237)
    public static let footerInk = (r: 134, g: 134, b: 136)
    /// The slider while the pointer is on it: the fill up to the pointer, the track after it.
    public static let sliderFillTop = (r: 245, g: 179, b: 115)
    public static let sliderFillBottom = (r: 242, g: 164, b: 86)
    public static let sliderTrackTop = (r: 175, g: 175, b: 180)
    public static let sliderTrackBottom = (r: 160, g: 160, b: 164)
    /// The most candidates the slider steps through, and the most matches one may have.
    public static let maxCandidates = 15
    public static let maxMatches = 100

    /// Which candidate the slider is on with the pointer at `fraction` of its width.
    public static func candidateIndex(fraction: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, Int((fraction * Double(count)).rounded(.down))))
    }

    /// A colour measured on Arc's screen, in the display's space (Display P3), as CSS: an `rgb()`
    /// of the same numbers would be taken for sRGB and come out paler (blue +25 on the yellow).
    static func p3(_ c: (r: Int, g: Int, b: Int), _ alpha: Double = 1) -> String {
        func f(_ v: Int) -> String { String(format: "%.4f", Double(v) / 255) }
        return "color(display-p3 \(f(c.r)) \(f(c.g)) \(f(c.b))" + (alpha < 1 ? " / \(alpha))" : ")")
    }

    /// The page's side of Zap: highlight, the confirm popover and the dim, drawn in a closed shadow
    /// root over the page. Cra polls `takeExpression` for what the popover zapped.
    public static let script = """
    (()=>{if(window.__craZap)return;
    const host=document.createElement('cra-zap'),root=host.attachShadow({mode:'closed'});
    host.style.cssText='all:initial;position:fixed;inset:0;z-index:2147483647;pointer-events:none';
    root.innerHTML=`<style>
    *{box-sizing:border-box;font-family:-apple-system,BlinkMacSystemFont,sans-serif;-webkit-font-smoothing:antialiased}
    .hl{position:fixed;border:1px solid \(p3(highlight, highlightBorderAlpha));border-radius:3px}
    .dim{position:fixed;inset:0;background:rgba(0,0,0,.36);display:none}
    .pop{position:fixed;display:none;min-width:364px;border-radius:14px;overflow:hidden;pointer-events:auto;
    background:linear-gradient(\(p3(popoverTop)),\(p3(popoverBottom)));box-shadow:0 0 0 .5px rgba(0,0,0,.2),0 6px 20px rgba(0,0,0,.25)}
    .row{display:flex;gap:9px;padding:9.5px 9px}
    button{all:unset;height:39px;padding:0 9px;border-radius:9px;color:#fff;font-size:15px;line-height:39px;white-space:nowrap;cursor:default}
    .this{background:linear-gradient(\(p3((236, 94, 82))),\(p3((229, 60, 47))))}
    .rel{flex:1;position:relative;overflow:hidden;background:linear-gradient(\(p3((240, 129, 87))),\(p3((233, 97, 46))))}
    .rel.scrub{background:linear-gradient(\(p3(sliderTrackTop)),\(p3(sliderTrackBottom)))}
    .rel i{position:absolute;left:0;top:0;bottom:0;width:0;display:none;background:linear-gradient(\(p3(sliderFillTop)),\(p3(sliderFillBottom)))}
    .rel.scrub i{display:block}.rel span{position:relative}
    .cancel{background:linear-gradient(\(p3((124, 124, 124))),\(p3((90, 90, 90))))}
    button:disabled{opacity:.45}
    .foot{height:32.5px;line-height:32.5px;padding:0 13px;background:\(p3(popoverFooter));color:\(p3(footerInk));font-size:11px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .foot b{font-weight:400;margin-right:6px}
    </style><div class=dim></div><div class=hls></div><div class=pop><div class=row><button class=this>Zap this</button>
    <button class=rel><i></i><span>Zap all related elements</span></button><button class=cancel>Cancel</button></div><div class=foot><b></b><span></span></div></div>`;
    // The fill multiplies the page under it (white text turns the yellow, the background a dark
    // tint); a host of its own, since a stacking context can only blend with what's below it.
    const tint=document.createElement('cra-zap-tint');
    tint.style.cssText='all:initial;position:fixed;inset:0;z-index:2147483646;pointer-events:none;mix-blend-mode:multiply';
    document.documentElement.append(tint,host);
    const hls=root.querySelector('.hls'),dim=root.querySelector('.dim'),pop=root.querySelector('.pop');
    const rel=root.querySelector('.rel'),fill=rel.querySelector('i');
    const count=s=>{try{return document.querySelectorAll(s).length}catch(e){return 0}};
    const esc=CSS.escape,ok=c=>/^[A-Za-z_-][\\w-]*$/.test(c)&&c.length<=32&&(c.match(/\\d/g)||[]).length<=2;
    const page=e=>!e||e===document.body||e===document.documentElement||e===host;
    const part=e=>e.tagName.toLowerCase()+[...e.classList].filter(ok).map(c=>'.'+esc(c)).join('');
    const idOf=e=>e.id&&ok(e.id)&&count('#'+esc(e.id))===1?'#'+esc(e.id):null;
    const thisSel=e=>{const id=idOf(e);if(id)return id;if(count(part(e))===1)return part(e);const p=[];
    for(let n=e;n&&!page(n);n=n.parentElement){const nid=idOf(n);if(nid){p.unshift(nid);break}
    const same=n.parentElement?[...n.parentElement.children].filter(x=>x.tagName===n.tagName):[n];
    p.unshift(part(n)+(same.length>1?':nth-of-type('+(same.indexOf(n)+1)+')':''));const s=p.join(' > ');if(count(s)===1)return s}
    return p.join(' > ')||part(e)};
    // Words a page's own class names use; a name with none of them and runs of digits or consonants
    // is generated ("css-1x2y3z") and makes a poor selector.
    const words=['ad','article','author','banner','body','button','card','comment','container','content','date','entry','feed','footer','grid','header','icon','image','item','label','line','link','list','logo','main','media','menu','meta','nav','news','page','post','promo','row','search','section','sidebar','social','sponsor','story','tag','text','thing','time','title','user','video','widget','wrapper'];
    const known=s=>words.some(w=>s.toLowerCase().includes(w));
    const generated=s=>!known(s)&&((s.match(/[0-9]/g)||[]).length>2||/[bcdfghjklmnpqrstvwxz]{5}/i.test(s));
    const plain=v=>v.length<=40&&!/["{};@<]/.test(v)&&!v.includes(String.fromCharCode(92))&&!v.includes(String.fromCharCode(10));
    const semantic=new Set(['a','article','aside','blockquote','button','figure','footer','form','h1','h2','h3','h4','h5','h6','header','img','li','main','nav','p','picture','section','svg','table','td','tr','video']);
    // A node's terms and how readable each is.
    const terms=n=>{const t=[],tag=n.tagName.toLowerCase();if(/^[a-z][a-z0-9-]*$/.test(tag))t.push([tag,semantic.has(tag)||tag.includes('-')?.5:-.1]);
    if(n.id&&ok(n.id)&&!generated(n.id))t.push(['#'+n.id,known(n.id)?1:.2]);
    for(const c of n.classList)if(ok(c)&&!generated(c))t.push(['.'+c,known(c)?1:.3]);
    for(const a of ['role','aria-label','data-testid','itemprop']){const v=n.getAttribute(a);if(v&&plain(v))t.push(['['+a+'="'+v+'"]',a==='data-testid'?1:.6])}
    // Where it sits among its siblings, as Arc's candidates use it too.
    const p=n.parentElement;if(p&&p.children.length>1){const k=[...p.children].indexOf(n);
    t.push([k===0?':first-child':k===p.children.length-1?':last-child':':nth-child('+(k+1)+')',-.1])}
    return t};
    // Selectors for e from 1 match up to \(maxMatches), one per count, fewest first, at most \(maxCandidates).
    const cands=e=>{const best=new Map(),tried=new Set();
    const add=(s,score)=>{if(tried.has(s)||tried.size>600)return;tried.add(s);let n;
    try{if(!e.matches(s)||e.querySelector(s))return;n=document.querySelectorAll(s).length}catch(x){return}
    if(n<2||n>\(maxMatches))return;score-=s.length/200;const b=best.get(n);if(!b||score>b.score)best.set(n,{s,n,score})};
    const own=terms(e),tag=e.tagName.toLowerCase();
    for(const [t,v] of own){add(t,v);if(t!==tag)add(tag+t,v+.2)}
    let a=e.parentElement;for(let d=1;a&&!page(a)&&d<=4;d++,a=a.parentElement)for(const [at,av] of terms(a))for(const [t,v] of own){
    add(at+' '+t,av+v-.1*d);if(d===1)add(at+' > '+t,av+v-.15)}
    let list=[...best.values()].sort((x,y)=>x.n-y.n);
    if(list.length>\(maxCandidates)-1){const kept=new Map();for(const c of list){const k=Math.floor(Math.log10(c.n)*6);if(!kept.has(k))kept.set(k,c)}list=[...kept.values()].slice(0,\(maxCandidates)-1)}
    const one=thisSel(e);return [{s:one,n:count(one)},...list]};
    const queue=[];let over=null,held=null;
    const box=e=>{const r=e.getBoundingClientRect();return {x:r.left-4,y:r.top-4,w:r.width+8,h:r.height+8}};
    const show=(el,b)=>{el.style.display='block';el.style.left=b.x+'px';el.style.top=b.y+'px';if(b.w!=null){el.style.width=b.w+'px';el.style.height=b.h+'px'}};
    // One highlight (a border, and a fill that multiplies the page) per lit element.
    const light=els=>{while(hls.children.length<els.length){hls.append(document.createElement('div'));hls.lastChild.className='hl';
    const f=document.createElement('div');f.style.cssText='position:fixed;background:\(p3(highlight));border-radius:3px';tint.append(f)}
    [...hls.children].forEach((h,i)=>{const f=tint.children[i];if(i<els.length){const b=box(els[i]);show(h,b);show(f,b)}else h.style.display=f.style.display='none'})};
    let lit=0;
    const draw=()=>{const e=held?held.el:over;if(!e||!e.isConnected){light([]);lit=0;pop.style.display='none';return}
    const c=held&&held.cands[held.idx];const els=c&&held.idx>0?[...document.querySelectorAll(c.s)]:[e];light(els);lit=els.length;
    if(held){const b=box(e),w=Math.max(364,b.w+3),ph=91;let x=Math.min(Math.max(0,b.x-2),innerWidth-w),y=b.y+b.h+8;
    if(y+ph>innerHeight&&b.y-8-ph>=0)y=b.y-8-ph;pop.style.width=w+'px';show(pop,{x,y})}else pop.style.display='none'};
    const close=()=>{held=null;over=null;rel.classList.remove('scrub');draw()};
    // The slider: the pointer at fraction f of its width (null: off it, the element alone).
    const foot=()=>{const c=held.cands[held.idx];root.querySelector('.foot b').textContent=String(c.n);root.querySelector('.foot span').textContent=c.s};
    const scrub=f=>{if(!held)return;rel.classList.toggle('scrub',f!=null);
    if(f==null)held.idx=0;else{const n=held.cands.length;held.idx=Math.min(n-1,Math.max(0,Math.floor(f*n)));fill.style.width=Math.max(0,Math.min(1,f))*100+'%'}
    foot();draw()};
    rel.addEventListener('mousemove',ev=>{const r=rel.getBoundingClientRect();scrub((ev.clientX-r.left)/r.width)});
    rel.addEventListener('mouseleave',()=>scrub(null));
    const zap=(sel)=>{queue.push(sel);close()};
    root.querySelector('.this').onclick=ev=>{ev.stopPropagation();if(held)zap(held.this)};
    rel.onclick=ev=>{ev.stopPropagation();if(held)zap(held.cands[held.idx].s)};
    root.querySelector('.cancel').onclick=ev=>{ev.stopPropagation();close()};
    const move=ev=>{if(held||dimmed||ev.target===host)return;const t=ev.target;const e=page(t)?null:t;if(e!==over){over=e;draw()}};
    // Only the popover takes the pointer in the (closed) shadow root: what reaches the host is its.
    const block=ev=>{if(ev.target===host)return;ev.preventDefault();ev.stopPropagation();ev.stopImmediatePropagation()};
    const click=ev=>{if(ev.target===host)return;block(ev);const t=ev.target;if(page(t)||dimmed)return;
    if(held){close();return}const cs=cands(t);held={el:t,this:cs[0].s,cands:cs,idx:0};
    foot();rel.disabled=cs.length<2;draw()};
    let dimmed=false;
    for(const t of ['pointerdown','mousedown','pointerup','mouseup'])document.addEventListener(t,block,true);
    document.addEventListener('mousemove',move,true);document.addEventListener('click',click,true);addEventListener('scroll',draw,true);addEventListener('resize',draw);
    const rect=el=>{if(el.style.display!=='block')return null;const r=el.getBoundingClientRect();return [r.left,r.top,r.width,r.height].map(Math.round)};
    window.__craZap={take(){return queue.length?JSON.stringify(queue.splice(0)):''},
    press(k){const b=root.querySelector({this:'.this',related:'.rel',cancel:'.cancel'}[k]);if(b&&held&&!b.disabled)b.click()},
    scrub,
    state(){return JSON.stringify({highlight:hls.firstChild?rect(hls.firstChild):null,popover:rect(pop),dim:dim.style.display==='block',lit,
    footer:held?root.querySelector('.foot').textContent:null,candidates:held?held.cands.map(c=>c.n):null,selectors:held?held.cands.map(c=>c.s):null})},
    dim(on){dimmed=!!on;dim.style.display=on?'block':'none';if(on)close()},
    stop(){for(const t of ['pointerdown','mousedown','pointerup','mouseup'])document.removeEventListener(t,block,true);
    document.removeEventListener('mousemove',move,true);document.removeEventListener('click',click,true);removeEventListener('scroll',draw,true);removeEventListener('resize',draw);
    host.remove();tint.remove();delete window.__craZap}}})()
    """

    /// What the popover zapped since the last call, as a JSON array of selectors; "" for nothing.
    public static let takeExpression = "window.__craZap?window.__craZap.take():''"
    public static let stopExpression = "window.__craZap&&window.__craZap.stop()"
    public static func dimExpression(_ on: Bool) -> String { "window.__craZap&&window.__craZap.dim(\(on))" }

    /// The selectors `takeExpression` returned. The page answers this, so only plain selectors pass:
    /// one that closes the rule or opens a block would put the page's own CSS into the boost.
    public static func parseTaken(_ json: String) -> [String] {
        guard !json.isEmpty, let a = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else { return [] }
        return a.filter(isPlainSelector)
    }

    public static func isPlainSelector(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 500 && !s.contains(where: { "{};@<\\".contains($0) || $0.isNewline })
    }
}

extension Boost {
    /// Zap: hide what `selector` matches (once).
    public mutating func zap(_ selector: String) {
        if !selector.isEmpty, !zapped.contains(selector) { zapped.append(selector) }
    }

    /// A shelf cell's click: show it again.
    public mutating func unzap(_ selector: String) {
        zapped.removeAll { $0 == selector }
    }
}
