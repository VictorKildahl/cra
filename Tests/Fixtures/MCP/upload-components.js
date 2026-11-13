// Web components for shadow-upload.html and upload-frame.html. Open shadow roots, hidden file inputs.
function report(id, input) {
  input.addEventListener('change', event => {
    document.getElementById(id).textContent = (event.isTrusted ? 'trusted ' : 'untrusted ') + Array.from(input.files, file => file.name).join(',');
  });
}
function component(name, html, wire) {
  customElements.define(name, class extends HTMLElement {
    connectedCallback() {
      if (this.shadowRoot) return;
      const root = this.attachShadow({mode: 'open'});
      root.innerHTML = html;
      wire(root, this);
    }
  });
}
// reddit.com's settings-dropzone: a hidden input and a button that opens its chooser.
component('settings-dropzone',
  '<input type="file" accept="image/png,image/jpeg" hidden><button type="button">Drag and drop or browse your device</button>',
  (root, host) => { root.querySelector('button').onclick = () => root.querySelector('input').click(); report(host.dataset.result, root.querySelector('input')); });
// settings-avatar-image-upload: the dropzone sits in another component's shadow root.
component('avatar-upload', '<settings-dropzone data-result="avatar-result"></settings-dropzone>', () => {});
// A label for one of two inputs in the same shadow root: only the label tells them apart.
component('banner-upload',
  '<label for="banner-file">Upload a banner</label><input id="banner-file" type="file" hidden><input id="banner-extra" type="file" hidden>',
  root => { report('banner-result', root.querySelector('#banner-file')); report('banner-result', root.querySelector('#banner-extra')); });
// The page's own button is slotted into the component that holds the input.
component('drop-zone', '<slot></slot><input type="file" hidden>',
  (root, host) => report(host.dataset.result, root.querySelector('input')));
// Two inputs behind one button: which one is meant can't be told.
component('pair-upload', '<button type="button">Browse either</button><input type="file" hidden><input type="file" hidden>', () => {});
