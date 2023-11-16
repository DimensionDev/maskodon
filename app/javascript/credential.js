/* eslint-disable promise/catch-or-return */
/* eslint-disable import/no-unresolved */
import * as WebAuthnJSON from "@github/webauthn-json/browser-ponyfill"
import * as Cbor from "cbor-web"

/**
 * Get public key object from credentials
 * @param {WebAuthnJSON.RegistrationPublicKeyCredential} credentials
 */
function getPublicKeyInHex(credentials) {
    // The attestationObject was was encoded as CBOR.
    const attestationObject = Cbor.default.decode(
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
    const publicKeyObject = Cbor.default.decode(publicKeyBytes);

    console.log("[DEBUG] Public Key Object");
    console.log(publicKeyObject);

    const kty = publicKeyObject.get(1);
    const alg = publicKeyObject.get(3);

    // ES256
    if (kty === 2 && alg === -7) {
      const x = Buffer.from(publicKeyObject.get(-2)).toString('hex');
      const y = Buffer.from(publicKeyObject.get(-3)).toString('hex');
      return `0x${x}${y}`
    } else {
      throw new Error('Not supported key algorithm.')
    }
}

async function getSignPayload(avatar, publicKeyInHex) {
  const response = await fetch('https://proof-service.nextnext.id/v1/subkey/payload', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        avatar,
        algorighm: 'es256',
        public_key: publicKeyInHex,
        rp_id: 'mastodon.firefly.land',
      })
    })
    const json = await response.json()
    return json.sign_payload
}

function sendDocumentEvent(type, requestArguments) {
  return new Promise((resolve, reject) => {
    const onResponse = (event) => {
      if (typeof event.detail.reason === 'string') reject(event.detail.reason)
      else resolve(event.detail)
    }

    document.addEventListener('documentResponse', onResponse, { once: true })

    const ab = new AbortController()
    ab.signal.addEventListener('abort', () => {
      document.removeEventListener('documentResponse', onResponse)
      reject('Sign payload timeout.')
    })

    document.dispatchEvent(new CustomEvent('documentRequest', {
      detail: {
        type,
        requestArguments,
      },
      bubbles: true,
    }))

    // timeout for 3 minutes
    setTimeout(() => ab.abort(), 3 * 60 * 1000)
  })
}

async function bindSubkey(name, avatar, publicKeyInHex, signature) {
  const response = await fetch('https://proof-service.nextnext.id/v1/subkey', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      avatar,
      algorithm: 'es256',
      public_key: publicKeyInHex,
      rp_id: 'mastodon.firefly.land',
      name,
      signature,
    })
  })
  return response.json()
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
      // window.location.replace(encodeURI(original_url))
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

  console.log('DEBUG: create options')
  console.log(data)

  const options = WebAuthnJSON.parseCreationOptionsFromJSON({ "publicKey": create_options })
  WebAuthnJSON.create(options).then(async (credentials) => {
    const publicKeyInHex = getPublicKeyInHex(credentials)

    const avatar = await sendDocumentEvent('get_avatar')
    const payload = await getSignPayload(avatar, publicKeyInHex)
    const signature = await sendDocumentEvent('sign_payload', payload)

    await bindSubkey(create_options.user.name, avatar, publicKeyInHex, signature)

    // save the credential id in localstorage
    localStorage.setItem('dimension_webauthn_credentials', JSON.stringify({
      id: credentials.id,
      avatar,
      publicKeyInHex,
      createdAt: Date.now(),
    }))

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
