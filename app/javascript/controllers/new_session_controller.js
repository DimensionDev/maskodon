/* eslint-disable promise/catch-or-return */
/* eslint-disable import/no-anonymous-default-export */
/* eslint-disable import/no-unresolved */
import { Controller } from "@hotwired/stimulus"
import * as Credential from "credential";

export default class extends Controller {
  encode(buffer) {
    const base64 = window.btoa(String.fromCharCode(...new Uint8Array(buffer)));
    return base64.replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  }
  decode(base64url) {
    const base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');
    const binStr = window.atob(base64);
    const bin = new Uint8Array(binStr.length);
    for (let i = 0; i < binStr.length; i++) {
      bin[i] = binStr.charCodeAt(i);
    }
    return bin.buffer;
  }
  async connect() {
    if (
      typeof window.PublicKeyCredential !== 'undefined'
      && typeof window.PublicKeyCredential.isConditionalMediationAvailable === 'function'
    ) {

    const available = await window.PublicKeyCredential.isConditionalMediationAvailable()
    if(available) {
      const form =document.getElementById('sign_in_form')
      if(form) {
        let newChallengeURL = new URL(form.dataset.challengeUrl)
        const data =new FormData()
        data.set('test', 'test')
       await fetch(newChallengeURL, {
          method: "POST",
          headers: new Headers(),
          body: data,
          credentials: 'include'
        }).then(async response => {
          const result = await response.json()
          if(result.get_options) {
            Credential.get(result)
          }

        })


      }
    }

    }
  }

  submit(event) {
    console.log("new-session click", event);
    event.preventDefault();

    const headers = new Headers();
    const action = event.target.action;
    const options = {
      method: event.target.method,
      headers: headers,
      body: new FormData(event.target)
    };

    fetch(action, options).then((response) => {
      if (response.ok) {
        ok(response);
      } else {
        err(response);
      }
    });

    function ok(response) {
      response.json().then((data) => {
        console.log("new-session#ok: data", data)
        if(data.errors) {
          const message = data.errors.join(" ");
          const messageContainer = document.getElementById('login-error')

          if(messageContainer) {
            messageContainer.replaceChildren(message)
            messageContainer.style = "display: block"
          }
        } else {
          Credential.get(data);
        }

      }).catch((error) => {
        console.log(error)
      });
    }

    function err(response) {
      console.log("new-session Error", response);
      response.json().then((json) => {
        const message = response.statusText + " - " + json.errors.join(" ");
        console.log("new-session text", message)
        Credential.displayError(message);
      });
    }
  }
}

