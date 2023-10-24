function base64urlToBuffer(e) {
    const r = "==".slice(0, (4 - e.length % 4) % 4);
    const t = e.replace(/-/g, "+").replace(/_/g, "/") + r;
    const n = atob(t);
    const o = new ArrayBuffer(n.length);
    const i = new Uint8Array(o);
    for (let e = 0; e < n.length; e++)
        i[e] = n.charCodeAt(e);
    return o
}
function bufferToBase64url(e) {
    const r = new Uint8Array(e);
    let t = "";
    for (const e of r)
        t += String.fromCharCode(e);
    const n = btoa(t);
    const o = n.replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
    return o
}
var e = "copy";
var r = "convert";
function convert(t, n, o) {
    if (n === e)
        return o;
    if (n === r)
        return t(o);
    if (n instanceof Array)
        return o.map((e=>convert(t, n[0], e)));
    if (n instanceof Object) {
        const e = {};
        for (const [r,i] of Object.entries(n)) {
            if (i.derive) {
                const e = i.derive(o);
                void 0 !== e && (o[r] = e)
            }
            if (r in o)
                null != o[r] ? e[r] = convert(t, i.schema, o[r]) : e[r] = null;
            else if (i.required)
                throw new Error(`Missing key: ${r}`)
        }
        return e
    }
}
function derived(e, r) {
    return {
        required: true,
        schema: e,
        derive: r
    }
}
function required(e) {
    return {
        required: true,
        schema: e
    }
}
function optional(e) {
    return {
        required: false,
        schema: e
    }
}
var t = {
    type: required(e),
    id: required(r),
    transports: optional(e)
};
var n = {
    appid: optional(e),
    appidExclude: optional(e),
    credProps: optional(e)
};
var o = {
    appid: optional(e),
    appidExclude: optional(e),
    credProps: optional(e)
};
var i = {
    publicKey: required({
        rp: required(e),
        user: required({
            id: required(r),
            name: required(e),
            displayName: required(e)
        }),
        challenge: required(r),
        pubKeyCredParams: required(e),
        timeout: optional(e),
        excludeCredentials: optional([t]),
        authenticatorSelection: optional(e),
        attestation: optional(e),
        extensions: optional(n)
    }),
    signal: optional(e)
};
var a = {
    type: required(e),
    id: required(e),
    rawId: required(r),
    authenticatorAttachment: optional(e),
    response: required({
        clientDataJSON: required(r),
        attestationObject: required(r),
        transports: derived(e, (e=>{
            var r;
            return (null == (r = e.getTransports) ? void 0 : r.call(e)) || []
        }
        ))
    }),
    clientExtensionResults: derived(o, (e=>e.getClientExtensionResults()))
};
var u = {
    mediation: optional(e),
    publicKey: required({
        challenge: required(r),
        timeout: optional(e),
        rpId: optional(e),
        allowCredentials: optional([t]),
        userVerification: optional(e),
        extensions: optional(n)
    }),
    signal: optional(e)
};
var s = {
    type: required(e),
    id: required(e),
    rawId: required(r),
    authenticatorAttachment: optional(e),
    response: required({
        clientDataJSON: required(r),
        authenticatorData: required(r),
        signature: required(r),
        userHandle: required(r)
    }),
    clientExtensionResults: derived(o, (e=>e.getClientExtensionResults()))
};
function createRequestFromJSON(e) {
    return convert(base64urlToBuffer, i, e)
}
function createResponseToJSON(e) {
    return convert(bufferToBase64url, a, e)
}
function getRequestFromJSON(e) {
    return convert(base64urlToBuffer, u, e)
}
function getResponseToJSON(e) {
    return convert(bufferToBase64url, s, e)
}
function supported() {
    return !!(navigator.credentials && navigator.credentials.create && navigator.credentials.get && window.PublicKeyCredential)
}
async function create(e) {
    const r = await navigator.credentials.create(e);
    r.toJSON = ()=>createResponseToJSON(r);
    return r
}
async function get(e) {
    const r = await navigator.credentials.get(e);
    r.toJSON = ()=>getResponseToJSON(r);
    return r
}
export {create, get, createRequestFromJSON as parseCreationOptionsFromJSON, getRequestFromJSON as parseRequestOptionsFromJSON, supported};

//# sourceMappingURL=webauthn-json.browser-ponyfill.js.map

