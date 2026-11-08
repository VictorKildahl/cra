import CoreGraphics
import Foundation

/// The Boost code panel's eyedropper (Arc 1.172.1: "Show Selector Picker" / "Hide Selector
/// Picker"; its menu after a click: "Copy selector for this", "Copy selector for related", "Zap
/// all related elements"). While it's on, the page outlines the element under the pointer and the
/// ones like it; a click is held for Cra (which polls `takeExpression`) and opens that menu.
///
/// The script is Cra's own: "this" is the shortest selector that matches only the element,
/// "related" the most specific one that matches it and 2 to 100 others like it.
public enum BoostPicker {
    public struct Pick: Equatable, Decodable, Sendable {
        /// Matches only the clicked element.
        public var this: String
        /// Matches it and others like it; equal to `this` when nothing is like it.
        public var related: String
        public var relatedCount: Int
        /// The click in CSS pixels from the viewport's top left, and the viewport's width.
        public var x: Double
        public var y: Double
        public var viewportWidth: Double

        public init(this: String, related: String, relatedCount: Int, x: Double, y: Double, viewportWidth: Double) {
            (self.this, self.related, self.relatedCount) = (this, related, relatedCount)
            (self.x, self.y, self.viewportWidth) = (x, y, viewportWidth)
        }

        /// "Copy selector for related" and "Zap all related elements" need something related.
        public var hasRelated: Bool { relatedCount > 1 && related != this }

        /// Where the click was in a page view `width` points wide, from its top left.
        public func point(inViewWidth width: Double) -> CGPoint {
            let scale = viewportWidth > 0 ? width / viewportWidth : 1
            return CGPoint(x: x * scale, y: y * scale)
        }
    }

    public enum Action: String, CaseIterable, Sendable {
        case copyThis, copyRelated, zapRelated

        public var title: String {
            switch self {
            case .copyThis: "Copy selector for this"
            case .copyRelated: "Copy selector for related"
            case .zapRelated: "Zap all related elements"
            }
        }

        public func isEnabled(for pick: Pick) -> Bool { self == .copyThis || pick.hasRelated }

        /// The selector the action copies or zaps.
        public func selector(for pick: Pick) -> String { self == .copyThis ? pick.this : pick.related }
    }

    /// The pick JSON `takeExpression` returned; nil for "" (no click yet) or anything else.
    public static func parse(_ json: String) -> Pick? {
        guard !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(Pick.self, from: Data(json.utf8))
    }

    /// Turns the picker on (once per page).
    public static let script = """
    (()=>{if(window.__craPick)return;
    const esc=CSS.escape,ok=c=>/^[A-Za-z_-][\\w-]*$/.test(c)&&c.length<=32&&(c.match(/\\d/g)||[]).length<=2;
    const count=s=>{try{return document.querySelectorAll(s).length}catch(e){return 0}};
    const page=e=>!e||e===document.body||e===document.documentElement;
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
    for(const s of c){const n=count(s);if(n>1&&n<=100)return [s,n]}return [thisSel(e),1]};
    const box=document.createElement('div');box.style.cssText='position:fixed;inset:0;pointer-events:none;z-index:2147483647';
    document.documentElement.append(box);let over=null,held=null,shown=null;
    const draw=()=>{box.replaceChildren();if(!over)return;const [rs]=relSel(over);let all=[];try{all=[...document.querySelectorAll(rs)]}catch(e){}
    if(!all.includes(over))all.push(over);for(const el of all.slice(0,101)){const r=el.getBoundingClientRect(),d=document.createElement('div'),me=el===over;
    d.style.cssText='position:fixed;box-sizing:border-box;border-radius:3px;left:'+r.left+'px;top:'+r.top+'px;width:'+r.width+'px;height:'+r.height+'px;'+
    (me?'border:2px solid #ff6a3d;background:rgba(255,106,61,.18)':'border:1.5px dashed #ff6a3d;background:rgba(255,106,61,.08)');box.append(d)}};
    const move=ev=>{if(held)return;const t=page(ev.target)?null:ev.target;if(t!==over){over=t;draw()}};
    const stop=ev=>{if(ev.target===box||page(ev.target))return;ev.preventDefault();ev.stopPropagation();ev.stopImmediatePropagation()};
    const click=ev=>{stop(ev);if(held||page(ev.target))return;over=ev.target;draw();const [r,n]=relSel(over);
    held={this:thisSel(over),related:r,relatedCount:n,x:ev.clientX,y:ev.clientY,viewportWidth:innerWidth}};
    const redraw=()=>{if(over)draw()};
    for(const t of ['pointerdown','mousedown','pointerup','mouseup'])document.addEventListener(t,stop,true);
    document.addEventListener('mouseover',move,true);document.addEventListener('click',click,true);addEventListener('scroll',redraw,true);
    window.__craPick={take(){if(!held||shown===held)return '';shown=held;return JSON.stringify(held)},
    resume(){held=null;shown=null},
    stop(){for(const t of ['pointerdown','mousedown','pointerup','mouseup'])document.removeEventListener(t,stop,true);
    document.removeEventListener('mouseover',move,true);document.removeEventListener('click',click,true);removeEventListener('scroll',redraw,true);
    box.remove();delete window.__craPick}}})()
    """

    /// The held click as JSON, once; "" when there's none.
    public static let takeExpression = "window.__craPick?window.__craPick.take():''"
    /// After the menu: outline and click again.
    public static let resumeExpression = "window.__craPick&&window.__craPick.resume()"
    public static let stopExpression = "window.__craPick&&window.__craPick.stop()"
}
