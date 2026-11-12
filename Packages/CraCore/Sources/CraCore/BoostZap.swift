import Foundation

/// Arc's Zap (Arc 1.172.2, measured in Victor's Arc on 12 Nov 2026; docs/arc-parity.md "Zap,
/// measured"). Zap on: the page shrinks for a 58 pt shelf under it, and the element under the
/// pointer takes a yellow highlight. A click asks first, in a popover under the element: "Zap this",
/// "Zap all related elements" or "Cancel", over a footer with the selector and how many elements it
/// matches. Each zap becomes a 38 pt cell on the shelf; a click on a cell unzaps it, and while the
/// pointer is on one the page dims and the hint reads "Restore <selector>". "Done" ends Zap.
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
    .hl{position:fixed;border:1px solid \(p3(highlight, highlightBorderAlpha));border-radius:3px;display:none}
    .dim{position:fixed;inset:0;background:rgba(0,0,0,.36);display:none}
    .pop{position:fixed;display:none;min-width:364px;border-radius:14px;overflow:hidden;pointer-events:auto;
    background:linear-gradient(\(p3(popoverTop)),\(p3(popoverBottom)));box-shadow:0 0 0 .5px rgba(0,0,0,.2),0 6px 20px rgba(0,0,0,.25)}
    .row{display:flex;gap:9px;padding:9.5px 9px}
    button{all:unset;height:39px;padding:0 9px;border-radius:9px;color:#fff;font-size:15px;line-height:39px;white-space:nowrap;cursor:default}
    .this{background:linear-gradient(\(p3((236, 94, 82))),\(p3((229, 60, 47))))}
    .rel{flex:1;background:linear-gradient(\(p3((240, 129, 87))),\(p3((233, 97, 46))))}
    .cancel{background:linear-gradient(\(p3((124, 124, 124))),\(p3((90, 90, 90))))}
    button:disabled{opacity:.45}
    .foot{height:32.5px;line-height:32.5px;padding:0 13px;background:\(p3(popoverFooter));color:\(p3(footerInk));font-size:11px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .foot b{font-weight:400;margin-right:6px}
    </style><div class=dim></div><div class=hl></div><div class=pop><div class=row><button class=this>Zap this</button>
    <button class=rel>Zap all related elements</button><button class=cancel>Cancel</button></div><div class=foot><b></b><span></span></div></div>`;
    // The fill multiplies the page under it (white text turns the yellow, the background a dark
    // tint); a host of its own, since a stacking context can only blend with what's below it.
    const tint=document.createElement('cra-zap-tint');
    tint.style.cssText='all:initial;position:fixed;z-index:2147483646;pointer-events:none;mix-blend-mode:multiply;background:\(p3(highlight));border-radius:3px;display:none';
    document.documentElement.append(tint,host);
    const hl=root.querySelector('.hl'),dim=root.querySelector('.dim'),pop=root.querySelector('.pop');
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
    const relSel=e=>{const t=e.tagName.toLowerCase(),own=part(e),c=[own],par=e.parentElement;
    const ps=page(par)?null:(idOf(par)||part(par));if(ps)c.push(ps+' > '+own);
    for(const k of [...e.classList].filter(ok))c.push(t+'.'+esc(k));if(ps)c.push(ps+' > '+t);
    for(const s of c){const n=count(s);if(n>1&&n<=100)return [s,n]}return null};
    const queue=[];let over=null,held=null;
    const box=e=>{const r=e.getBoundingClientRect();return {x:r.left-4,y:r.top-4,w:r.width+8,h:r.height+8}};
    const show=(el,b)=>{el.style.display='block';el.style.left=b.x+'px';el.style.top=b.y+'px';if(b.w!=null){el.style.width=b.w+'px';el.style.height=b.h+'px'}};
    const draw=()=>{const e=held?held.el:over;if(!e||!e.isConnected){hl.style.display=tint.style.display='none';pop.style.display='none';return}show(hl,box(e));show(tint,box(e));
    if(held){const b=box(e),w=Math.max(364,b.w+3),ph=91;let x=Math.min(Math.max(0,b.x-2),innerWidth-w),y=b.y+b.h+8;
    if(y+ph>innerHeight&&b.y-8-ph>=0)y=b.y-8-ph;pop.style.width=w+'px';show(pop,{x,y})}else pop.style.display='none'};
    const close=()=>{held=null;over=null;draw()};
    const zap=(sel)=>{queue.push(sel);close()};
    root.querySelector('.this').onclick=ev=>{ev.stopPropagation();if(held)zap(held.this)};
    root.querySelector('.rel').onclick=ev=>{ev.stopPropagation();if(held&&held.related)zap(held.related[0])};
    root.querySelector('.cancel').onclick=ev=>{ev.stopPropagation();close()};
    const move=ev=>{if(held||dimmed||ev.target===host)return;const t=ev.target;const e=page(t)?null:t;if(e!==over){over=e;draw()}};
    // Only the popover takes the pointer in the (closed) shadow root: what reaches the host is its.
    const block=ev=>{if(ev.target===host)return;ev.preventDefault();ev.stopPropagation();ev.stopImmediatePropagation()};
    const click=ev=>{if(ev.target===host)return;block(ev);const t=ev.target;if(page(t)||dimmed)return;
    if(held){close();return}const s=thisSel(t);held={el:t,this:s,related:relSel(t)};
    root.querySelector('.foot b').textContent=String(count(s));root.querySelector('.foot span').textContent=s;
    root.querySelector('.rel').disabled=!held.related;draw()};
    let dimmed=false;
    for(const t of ['pointerdown','mousedown','pointerup','mouseup'])document.addEventListener(t,block,true);
    document.addEventListener('mousemove',move,true);document.addEventListener('click',click,true);addEventListener('scroll',draw,true);addEventListener('resize',draw);
    const rect=el=>{if(el.style.display!=='block')return null;const r=el.getBoundingClientRect();return [r.left,r.top,r.width,r.height].map(Math.round)};
    window.__craZap={take(){return queue.length?JSON.stringify(queue.splice(0)):''},
    press(k){const b=root.querySelector({this:'.this',related:'.rel',cancel:'.cancel'}[k]);if(b&&held&&!b.disabled)b.click()},
    state(){return JSON.stringify({highlight:rect(hl),popover:rect(pop),dim:dim.style.display==='block',
    footer:held?root.querySelector('.foot').textContent:null,related:held&&held.related?held.related[0]:null})},
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
