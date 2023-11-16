import { createRoot }  from 'react-dom/client';

import './public-path';

import { IntlMessageFormat }  from 'intl-messageformat';
import { defineMessages } from 'react-intl';

import { delegate }  from '@rails/ujs';
import { createConfig, getAccount , InjectedConnector, configureChains, watchAccount, signMessage } from '@wagmi/core';
import { mainnet } from '@wagmi/core/chains';
import { CoinbaseWalletConnector } from '@wagmi/core/connectors/coinbaseWallet'
import { WalletConnectConnector } from '@wagmi/core/connectors/walletConnect'
import { infuraProvider } from '@wagmi/core/providers/infura'
import { createWeb3Modal, EIP6963Connector } from '@web3modal/wagmi'
import axios from 'axios';
import { throttle } from 'lodash';

import { start } from '../mastodon/common';
import { timeAgoString }  from '../mastodon/components/relative_timestamp';
import emojify  from '../mastodon/features/emoji/emoji';
import loadKeyboardExtensions from '../mastodon/load_keyboard_extensions';
import { loadLocale, getLocale } from '../mastodon/locales';
import { loadPolyfills } from '../mastodon/polyfills';
import ready from '../mastodon/ready';

import 'cocoon-js-vanilla';

const messages = defineMessages({
  usernameTaken: { id: 'username.taken', defaultMessage: 'That username is taken. Try another' },
  passwordExceedsLength: { id: 'password_confirmation.exceeds_maxlength', defaultMessage: 'Password confirmation exceeds the maximum password length' },
  passwordDoesNotMatch: { id: 'password_confirmation.mismatching', defaultMessage: 'Password confirmation does not match' },
  signUp: { id: 'auth.register', defaultMessage: 'Sign Up' },
  connect: { id: 'auth.connect', defaultMessage: 'Connect'}
});

start();

window.addEventListener('message', e => {
  const data = e.data || {};

  if (!window.parent || data.type !== 'setHeight') {
    return;
  }

  ready(() => {
    window.parent.postMessage({
      type: 'setHeight',
      id: data.id,
      height: document.getElementsByTagName('html')[0].scrollHeight,
    }, '*');
  });
});

function loaded() {
  const { messages: localeData } = getLocale();

  const locale = document.documentElement.lang;

  const dateTimeFormat = new Intl.DateTimeFormat(locale, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: 'numeric',
    minute: 'numeric',
  });

  const dateFormat = new Intl.DateTimeFormat(locale, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    timeFormat: false,
  });

  const timeFormat = new Intl.DateTimeFormat(locale, {
    timeStyle: 'short',
    hour12: false,
  });

  const formatMessage = ({ id, defaultMessage }, values) => {
    const messageFormat = new IntlMessageFormat(localeData[id] || defaultMessage, locale);
    return messageFormat.format(values);
  };

  [].forEach.call(document.querySelectorAll('.emojify'), (content) => {
    content.innerHTML = emojify(content.innerHTML);
  });

  [].forEach.call(document.querySelectorAll('time.formatted'), (content) => {
    const datetime = new Date(content.getAttribute('datetime'));
    const formattedDate = dateTimeFormat.format(datetime);

    content.title = formattedDate;
    content.textContent = formattedDate;
  });

  const isToday = date => {
    const today = new Date();

    return date.getDate() === today.getDate() &&
      date.getMonth() === today.getMonth() &&
      date.getFullYear() === today.getFullYear();
  };
  const todayFormat = new IntlMessageFormat(localeData['relative_format.today'] || 'Today at {time}', locale);

  [].forEach.call(document.querySelectorAll('time.relative-formatted'), (content) => {
    const datetime = new Date(content.getAttribute('datetime'));

    let formattedContent;

    if (isToday(datetime)) {
      const formattedTime = timeFormat.format(datetime);

      formattedContent = todayFormat.format({ time: formattedTime });
    } else {
      formattedContent = dateFormat.format(datetime);
    }

    content.title = formattedContent;
    content.textContent = formattedContent;
  });

  [].forEach.call(document.querySelectorAll('time.time-ago'), (content) => {
    const datetime = new Date(content.getAttribute('datetime'));
    const now      = new Date();

    const timeGiven = content.getAttribute('datetime').includes('T');
    content.title = timeGiven ? dateTimeFormat.format(datetime) : dateFormat.format(datetime);
    content.textContent = timeAgoString({
      formatMessage,
      formatDate: (date, options) => (new Intl.DateTimeFormat(locale, options)).format(date),
    }, datetime, now, now.getFullYear(), timeGiven);
  });

  const reactComponents = document.querySelectorAll('[data-component]');

  if (reactComponents.length > 0) {
    import(/* webpackChunkName: "containers/media_container" */ '../mastodon/containers/media_container')
      .then(({ default: MediaContainer }) => {
        [].forEach.call(reactComponents, (component) => {
          [].forEach.call(component.children, (child) => {
            component.removeChild(child);
          });
        });

        const content = document.createElement('div');

        const root = createRoot(content);
        root.render(<MediaContainer locale={locale} components={reactComponents} />);
        document.body.appendChild(content);
      })
      .catch(error => {
        console.error(error);
      });
  }

  delegate(document, '#user_account_attributes_username', 'input', throttle(({ target }) => {
    if (target.value && target.value.length > 0) {
      axios.get('/api/v1/accounts/lookup', { params: { acct: target.value } }).then(() => {
        target.setCustomValidity(formatMessage(messages.usernameTaken));
      }).catch(() => {
        target.setCustomValidity('');
      });
    } else {
      target.setCustomValidity('');
    }
  }, 500, { leading: false, trailing: true }));

  delegate(document, '#user_password,#user_password_confirmation', 'input', () => {
    const password = document.getElementById('user_password');
    const confirmation = document.getElementById('user_password_confirmation');
    if (!confirmation) return;

    if (confirmation.value && confirmation.value.length > password.maxLength) {
      confirmation.setCustomValidity(formatMessage(messages.passwordExceedsLength));
    } else if (password.value && password.value !== confirmation.value) {
      confirmation.setCustomValidity(formatMessage(messages.passwordDoesNotMatch));
    } else {
      confirmation.setCustomValidity('');
    }
  });

  delegate(document, '.status__content__spoiler-link', 'click', function() {
    const statusEl = this.parentNode.parentNode;

    if (statusEl.dataset.spoiler === 'expanded') {
      statusEl.dataset.spoiler = 'folded';
      this.textContent = (new IntlMessageFormat(localeData['status.show_more'] || 'Show more', locale)).format();
    } else {
      statusEl.dataset.spoiler = 'expanded';
      this.textContent = (new IntlMessageFormat(localeData['status.show_less'] || 'Show less', locale)).format();
    }

    return false;
  });

  [].forEach.call(document.querySelectorAll('.status__content__spoiler-link'), (spoilerLink) => {
    const statusEl = spoilerLink.parentNode.parentNode;
    const message = (statusEl.dataset.spoiler === 'expanded') ? (localeData['status.show_less'] || 'Show less') : (localeData['status.show_more'] || 'Show more');
    spoilerLink.textContent = (new IntlMessageFormat(message, locale)).format();
  });

  // 1. Define constants
  const projectId = 'd7bada49f9ce3d4d430dd39e5c2c48b0';

  // 2. Configure wagmi client
  const { chains, publicClient } = configureChains([mainnet],  [infuraProvider({ apiKey: '50676f4e9b9d4780a34fc8a503ff7f4f' })],)

  const metadata = {
    name: 'Web3Modal',
    description: 'Web3Modal Example',
    url: 'https://web3modal.com',
    icons: ['https://avatars.githubusercontent.com/u/37784886']
  }

  const wagmiConfig = createConfig({
    autoConnect: true,
    connectors: [
      new WalletConnectConnector({ chains, options: { projectId, showQrModal: false, metadata } }),
      new EIP6963Connector({ chains }),
      new InjectedConnector({ chains, options: { shimDisconnect: true } }),
      new CoinbaseWalletConnector({ chains, options: { appName: metadata.name } })
    ],
    publicClient
  })

  // 3. Create modal
  const modal = createWeb3Modal({ wagmiConfig, projectId, chains });

  const account = getAccount()
  const button = document.getElementById('register-button')

  const openModal = (event) => {
    event.preventDefault()
    event.stopPropagation()
    modal.open()
  }
  const listener = (account) => {
    if(!button) return
    if(account.isConnected) {
      button.removeEventListener('click', openModal)
      button.type = 'submit'
      button.innerText = formatMessage(messages.signUp)
    } else {
      button.innerText = formatMessage(messages.connect)
      button.addEventListener('click', openModal)
    }
  }

  listener(account)
  watchAccount(listener)
}

document.addEventListener('documentRequest', async (event) => {
  const handle = (type, requestArguments) => {
    switch (type) {
      case 'get_avatar':
        return '0x'
      case 'sign_payload':
        {
          return signMessage({
            message: requestArguments,
          })
      }
      default:
        throw new Error(`Unknown event type: ${type}`)
    }
  }

  document.dispatchEvent(new CustomEvent('signPayloadResponse', {
    detail: await handle(event.detail.type, event.detail.requestArguments)
  }))
})

delegate(document, '#edit_profile input[type=file]', 'change', ({ target }) => {
  const avatar = document.getElementById(target.id + '-preview');
  const [file] = target.files || [];
  const url = file ? URL.createObjectURL(file) : avatar.dataset.originalSrc;

  avatar.src = url;
});

delegate(document, '.input-copy input', 'click', ({ target }) => {
  target.focus();
  target.select();
  target.setSelectionRange(0, target.value.length);
});

delegate(document, '.input-copy button', 'click', ({ target }) => {
  const input = target.parentNode.querySelector('.input-copy__wrapper input');

  const oldReadOnly = input.readonly;

  input.readonly = false;
  input.focus();
  input.select();
  input.setSelectionRange(0, input.value.length);

  try {
    if (document.execCommand('copy')) {
      input.blur();
      target.parentNode.classList.add('copied');

      setTimeout(() => {
        target.parentNode.classList.remove('copied');
      }, 700);
    }
  } catch (err) {
    console.error(err);
  }

  input.readonly = oldReadOnly;
});


const toggleSidebar = () => {
  const sidebar = document.querySelector('.sidebar ul');
  const toggleButton = document.querySelector('.sidebar__toggle__icon');

  if (sidebar.classList.contains('visible')) {
    document.body.style.overflow = null;
    toggleButton.setAttribute('aria-expanded', 'false');
  } else {
    document.body.style.overflow = 'hidden';
    toggleButton.setAttribute('aria-expanded', 'true');
  }

  toggleButton.classList.toggle('active');
  sidebar.classList.toggle('visible');
};

delegate(document, '.sidebar__toggle__icon', 'click', () => {
  toggleSidebar();
});

delegate(document, '.sidebar__toggle__icon', 'keydown', e => {
  if (e.key === ' ' || e.key === 'Enter') {
    e.preventDefault();
    toggleSidebar();
  }
});

delegate(document, '.custom-emoji', 'mouseover', ({ target }) => target.src = target.getAttribute('data-original'));
delegate(document, '.custom-emoji', 'mouseout', ({ target }) => target.src = target.getAttribute('data-static'));

// Empty the honeypot fields in JS in case something like an extension
// automatically filled them.
delegate(document, '#registration_new_user,#new_user', 'submit', () => {
  ['user_website', 'user_confirm_password', 'registration_user_website', 'registration_user_confirm_password'].forEach(id => {
    const field = document.getElementById(id);
    if (field) {
      field.value = '';
    }
  });
});


function main() {
  ready(loaded);
}

loadPolyfills()
  .then(loadLocale)
  .then(main)
  .then(loadKeyboardExtensions)
  .catch(error => {
    console.error(error);
  });
