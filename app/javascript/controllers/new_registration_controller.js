/* eslint-disable promise/catch-or-return */
/* eslint-disable import/no-anonymous-default-export */
/* eslint-disable import/no-unresolved */
import { Controller } from "@hotwired/stimulus"
import * as Credential from "credential";

export default class extends Controller {
  connect() {
    console.log("new-registration connect");
  }

  submit(event) {
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

        if (data.create_options?.user) {
          Credential.create(data);
        } else if(data.errors && data.errors.length) {
          const message = data.errors.join(" ")
          const messageContainer = document.getElementById('registration-error')
          if(messageContainer) {
            messageContainer.replaceChildren(message)
            messageContainer.style = "display: block"
          }
        }
      });
    }

    function err(response) {

      console.log("new-registration Error", response);
    }
  }
}

