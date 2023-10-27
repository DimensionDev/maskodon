import * as WebAuthnJSON from "@github/webauthn-json/browser-ponyfill"
import { decode } from 'cbor'

/**
 * Get Publick Key from credentials
 * @param {WebAuthnJSON.RegistrationPublicKeyCredential} credentials
 */
function getPublicKeyObject(credentials) {
    // The attestationObject was was encoded as CBOR.
    const attestationObject = decode(
      credentials.response.attestationObject
    );

    const authData = attestationObject.authData;
    const dataView = new DataView(new ArrayBuffer(2));
    const idLenBytes = authData.slice(53, 55);
    idLenBytes.forEach((value, index) => dataView.setUint8(index, value));
    const credentialIdLength = dataView.getUint16(0);

    // get the credential ID
    const credentialId = authData.slice(55, 55 + credentialIdLength);

    // validate the credential ID
    if (
      Buffer.from(credentialId).toString("base64") !==
      Buffer.from(credentials.rawId).toString("base64")
    )
      throw new Error("Invalid credential ID");

    // get the public key object
    const publicKeyBytes = authData.slice(55 + credentialIdLength);

    // the publicKeyBytes are encoded again as CBOR
    return decode(publicKeyBytes);

}

/**
 * Get Publick Key from credentials
 * @param {WebAuthnJSON.RegistrationPublicKeyCredential} credentials
 * @returns {Object} The object with the following properties:
 * @property {string} challenge - The challenge string.
 * @property {boolean} crossOrigin - Whether the request is cross-origin (false in this case).
 * @property {string} origin - The origin URL.
 * @property {string} type - 'webauthn.create' | 'webauthn.get'
 */
function getClientDataJSON(credentials) {
  const decoder = new TextDecoder("utf-8");

  return JSON.parse(
    decoder.decode(credentials.response.clientDataJSON)
  )
}

function getCSRFToken() {
  var CSRFSelector = document.querySelector('meta[name="csrf-token"]')
  if (CSRFSelector) {
    return CSRFSelector.getAttribute("content")
  } else {
    return null
  }
}

function displayError(message) {
  const ele = document.querySelector('#message-box');
  const event = new CustomEvent('msg', { detail: { message: message}});
  ele.dispatchEvent(event);
  console.log("credential: event sent");
}

function callback(original_url, callback_url, body) {
  console.log("credential: in callback", original_url, callback_url, body);
  fetch(encodeURI(callback_url), {
    method: "POST",
    body: JSON.stringify(body),
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": getCSRFToken()
    },
    credentials: 'same-origin'
  }).then(function(response) {
    if (response.ok) {
      window.location.replace(encodeURI(original_url))
    } else if (response.status < 500) {
      console.log("credential: response not ok");
      response.text().then((text) => { displayError(text) });
    } else {
      console.log(response);
    }
  });
}


function clearCookie(cookieName) {
  document.cookie = cookieName + "=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;";
}

function create(data) {
  const { original_url, callback_url, create_options } = data
  const options = WebAuthnJSON.parseCreationOptionsFromJSON({ "publicKey": create_options })
  WebAuthnJSON.create(options).then((credentials) => {
    // save the credential id in localstorage
    localStorage.setItem('dimension_webauthn_credentials', {
      id: credentials.id,
      publicKeyObject: getPublicKeyObject(credentials),
      clientData: getClientDataJSON(credentials),
      at: Date.now(),
    })
    callback(original_url, callback_url, credentials);
  }).catch(function(error) {
    clearCookie('_mastodon_session');
    console.log("credential: create error", error);
  });

  console.log("credential: Creating new public key credential...");
}

function get(data) {
  const { original_url, callback_url, get_options } = data
  const options = WebAuthnJSON.parseRequestOptionsFromJSON({ "publicKey": get_options })
  WebAuthnJSON.get(options).then((credentials) => {
    callback(original_url, callback_url, credentials);
  }).catch(function(error) {
    clearCookie('_mastodon_session');
    console.log("credential: get error", error);
  });

  console.log("credential: Getting public key credential...");
}

export { create, get, displayError }

