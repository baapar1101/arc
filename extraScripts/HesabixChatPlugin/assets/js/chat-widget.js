( function () {
	'use strict';

	if ( typeof HESABIX_CHAT === 'undefined' ) {
		if ( typeof console !== 'undefined' && console.warn ) {
			console.warn( '[HesabixChat] HESABIX_CHAT تعریف نشد — اسکریپت localize نشده، public_key خالی است، یا ترتیب لود (فایل JS قبل از HESABIX_CHAT) اشتباه است.' );
		}
		return;
	}

	var cfg = HESABIX_CHAT;
	var STORAGE_VERSION = 1;

	function chatIsVerbose() {
		if ( cfg && cfg.debug ) {
			return true;
		}
		try {
			if ( typeof localStorage !== 'undefined' && localStorage.getItem( 'hesabix_chat_debug' ) === '1' ) {
				return true;
			}
			if ( typeof location !== 'undefined' && /[?&]hesabix_chat_debug=1(?:&|$)/.test( String( location.search || '' ) ) ) {
				return true;
			}
		} catch ( e0 ) {}
		return false;
	}
	function chatLog() {
		var a = [ '[HesabixChat]' ];
		for ( var i = 0; i < arguments.length; i++ ) {
			a.push( arguments[ i ] );
		}
		if ( typeof console !== 'undefined' && console.log ) {
			console.log.apply( console, a );
		}
	}
	function chatLogV() {
		if ( ! chatIsVerbose() ) {
			return;
		}
		var b = [ '[HesabixChat:verbose]' ];
		for ( var j = 0; j < arguments.length; j++ ) {
			b.push( arguments[ j ] );
		}
		if ( typeof console !== 'undefined' && console.log ) {
			console.log.apply( console, b );
		}
	}
	function chatWarn() {
		var c = [ '[HesabixChat]' ];
		for ( var k = 0; k < arguments.length; k++ ) {
			c.push( arguments[ k ] );
		}
		if ( typeof console !== 'undefined' && console.warn ) {
			console.warn.apply( console, c );
		}
	}

	chatLog( 'راه\u200cاندازی', {
		loadMode: cfg.loadMode,
		hasApiBase: Boolean( cfg.apiBase && String( cfg.apiBase ).length ),
		hasPublicKey: Boolean( cfg.publicKey && String( cfg.publicKey ).length ),
		hint: 'برای لاگ بیشتر: ?hesabix_chat_debug=1 در URL یا localStorage.hesabix_chat_debug=1'
	} );

	function simpleKey( s ) {
		var h = 0;
		for ( var i = 0; i < s.length; i++ ) {
			h = ( ( h << 5 ) - h ) + s.charCodeAt( i );
			h |= 0;
		}
		return 'h' + Math.abs( h ).toString( 36 );
	}

	function storageKey() {
		return 'hesabix_wp_crm_' + STORAGE_VERSION + '_' + simpleKey( cfg.apiBase + '|' + cfg.publicKey );
	}

	function getWsUrl() {
		var base = ( cfg.apiBase || '' ).replace( /\/$/, '' );
		if ( base.indexOf( 'https://' ) === 0 ) {
			return base.replace( 'https://', 'wss://' ) + '/ws/crm-chat';
		}
		if ( base.indexOf( 'http://' ) === 0 ) {
			return base.replace( 'http://', 'ws://' ) + '/ws/crm-chat';
		}
		return '';
	}

	function apiPath( p ) {
		return ( cfg.apiBase || '' ).replace( /\/$/, '' ) + p;
	}

	function loadSession() {
		try {
			var raw = localStorage.getItem( storageKey() );
			if ( ! raw ) {
				return null;
			}
			var o = JSON.parse( raw );
			if ( ! o || o.v !== STORAGE_VERSION || o.apiBase !== cfg.apiBase || o.publicKey !== cfg.publicKey ) {
				return null;
			}
			if ( ! o.visitor_token || ! o.conversation_id ) {
				return null;
			}
			return o;
		} catch ( e ) {
			return null;
		}
	}

	function saveSession( convId, token ) {
		var payload = {
			v: STORAGE_VERSION,
			apiBase: cfg.apiBase,
			publicKey: cfg.publicKey,
			conversation_id: convId,
			visitor_token: token
		};
		try {
			localStorage.setItem( storageKey(), JSON.stringify( payload ) );
		} catch ( e ) {}
	}

	function clearSession() {
		try {
			localStorage.removeItem( storageKey() );
		} catch ( e ) {}
	}

	function parseJsonSafe( text ) {
		try {
			return JSON.parse( text );
		} catch ( e ) {
			return null;
		}
	}

	function extractApiError( j ) {
		if ( ! j ) {
			return cfg.strings.errorGeneric;
		}
		var d = j.detail;
		if ( d && typeof d === 'object' && d.error && d.error.message ) {
			return d.error.message;
		}
		if ( d && d.message ) {
			return d.message;
		}
		if ( j.error && j.error.message ) {
			return j.error.message;
		}
		if ( j.message && typeof j.message === 'string' ) {
			return j.message;
		}
		return cfg.strings.errorGeneric;
	}

	function apiFetch( url, options ) {
		return fetch( url, options ).then( function ( res ) {
			return res.text().then( function ( text ) {
				var j = parseJsonSafe( text );
				if ( ! res.ok ) {
					throw new Error( extractApiError( j ) );
				}
				if ( j && j.success === false ) {
					throw new Error( extractApiError( j ) );
				}
				return j;
			} );
		} );
	}

	function startConversation( body ) {
		return apiFetch( apiPath( '/api/v1/public/crm-chat/conversations/start' ), {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify( {
				public_key: cfg.publicKey,
				first_name: body.first_name,
				last_name: body.last_name,
				email: body.email,
				phone: body.phone,
				page_url: window.location.href
			} )
		} ).then( function ( j ) {
			return j.data || j;
		} );
	}

	function postMessage( convId, token, body ) {
		return apiFetch( apiPath( '/api/v1/public/crm-chat/messages' ), {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify( {
				visitor_token: token,
				conversation_id: convId,
				body: body
			} )
		} ).then( function ( j ) {
			return j.data || j;
		} );
	}

	function visitorTokenHeaders( token ) {
		return { 'X-Visitor-Token': token };
	}

	function listMessages( convId, token, limit ) {
		var q = '?limit=' + ( limit || 100 );
		return apiFetch(
			apiPath( '/api/v1/public/crm-chat/conversations/' + convId + '/messages' ) + q,
			{ method: 'GET', headers: visitorTokenHeaders( token ) }
		).then( function ( j ) {
			var d = j.data || j;
			return ( d && d.items ) ? d.items : [];
		} );
	}

	/** علامت‌گذاری پیام‌های پشتیبان به‌عنوان خوانده‌شده (تا شناسه). */
	function markAgentMessagesRead( convId, token, upToId ) {
		if ( ! upToId || upToId < 1 ) {
			return Promise.resolve();
		}
		return apiFetch( apiPath( '/api/v1/public/crm-chat/conversations/' + convId + '/read' ), {
			method: 'POST',
			headers: Object.assign( { 'Content-Type': 'application/json' }, visitorTokenHeaders( token ) ),
			body: JSON.stringify( { up_to_message_id: upToId } )
		} ).catch( function () {} );
	}

	function maxAgentMessageId( items ) {
		var m = 0;
		( items || [] ).forEach( function ( x ) {
			if ( ( ( x.sender_role || '' ).toString() ) !== 'agent' || x.id == null ) {
				return;
			}
			var id = +x.id;
			if ( id > m ) {
				m = id;
			}
		} );
		return m;
	}

	function syncMarkAgentRead( items ) {
		if ( ! state.session ) {
			return;
		}
		var up = maxAgentMessageId( items );
		if ( up > 0 ) {
			markAgentMessagesRead( state.session.conversation_id, state.session.visitor_token, up );
		}
	}

	/** دانلود فایل ضمیمه بدون گذاشتن توکن در URL (هدر X-Visitor-Token). */
	function downloadVisitorFile( convId, token, fileId, displayName ) {
		var u = apiPath( '/api/v1/public/crm-chat/conversations/' + convId + '/files/' + encodeURIComponent( fileId ) + '/download' );
		return fetch( u, { method: 'GET', headers: visitorTokenHeaders( token ) } ).then( function ( res ) {
			if ( ! res.ok ) {
				return res.text().then( function ( text ) {
					var j = parseJsonSafe( text );
					throw new Error( extractApiError( j ) );
				} );
			}
			var fname = displayName || 'file';
			var cd = res.headers.get( 'Content-Disposition' );
			if ( cd ) {
				var mStar = cd.match( /filename\*=UTF-8''([^;\n]+)/i );
				var mQ = cd.match( /filename="([^"]+)"/i );
				if ( mStar && mStar[1] ) {
					try {
						fname = decodeURIComponent( mStar[1].trim() );
					} catch ( e0 ) {
						fname = mStar[1].trim();
					}
				} else if ( mQ && mQ[1] ) {
					fname = mQ[1].trim();
				}
			}
			return res.blob().then( function ( blob ) {
				var objUrl = URL.createObjectURL( blob );
				var a = document.createElement( 'a' );
				a.href = objUrl;
				a.download = fname;
				a.rel = 'noopener';
				document.body.appendChild( a );
				a.click();
				a.remove();
				URL.revokeObjectURL( objUrl );
			} );
		} );
	}

	function postFile( convId, token, file, caption ) {
		var fd = new FormData();
		fd.append( 'visitor_token', token );
		fd.append( 'conversation_id', String( convId ) );
		fd.append( 'caption', caption || '' );
		fd.append( 'file', file );
		return apiFetch( apiPath( '/api/v1/public/crm-chat/messages/file' ), {
			method: 'POST',
			body: fd
		} ).then( function ( j ) {
			return j.data || j;
		} );
	}

	function posClass( pos ) {
		var map = {
			'bottom-right': 'hesabix-pos-bottom-right',
			'bottom-left': 'hesabix-pos-bottom-left',
			'top-right': 'hesabix-pos-top-right',
			'top-left': 'hesabix-pos-top-left'
		};
		return map[ pos ] || 'hesabix-pos-bottom-right';
	}

	function formatTime( iso ) {
		if ( ! iso ) {
			return '';
		}
		try {
			var d = new Date( iso );
			return d.toLocaleString();
		} catch ( e ) {
			return String( iso );
		}
	}

	var state = {
		open: false,
		session: null,
		messages: [],
		ws: null,
		pollTimer: null,
		usePoll: false,
		agentTyping: false,
		agentTypingTimer: null,
		visitorTypingSendTimer: null,
		visitorTypingStopTimer: null
	};

	function stopPoll() {
		if ( state.pollTimer ) {
			clearInterval( state.pollTimer );
			state.pollTimer = null;
		}
	}

	function startPoll( convId, token ) {
		stopPoll();
		state.pollTimer = setInterval( function () {
			listMessages( convId, token, 100 ).then( function ( items ) {
				if ( items.length !== state.messages.length ) {
					state.messages = items;
					renderMessages();
					syncMarkAgentRead( items );
				}
			} ).catch( function () {} );
		}, 25000 );
	}

	var host = document.getElementById( 'hesabix-chat-host' );
	if ( ! host ) {
		chatWarn( 'عنصر DOM با id برابر hesabix-chat-host یافت نشد. در حالت shortcode باید شورتکد [hesabix_chat] در همان صفحه باشد؛ در بیلدر ممکن است asset لود نشود. در load_mode=global باید فوتر قالب همان id را چاپ کند.' );
		return;
	}

	try {
	var root = document.createElement( 'div' );
	var uiPreset = ( cfg.uiPreset && cfg.uiPreset.toString() ) || 'default';
	if ( [ 'default', 'minimal', 'colorful' ].indexOf( uiPreset ) < 0 ) {
		uiPreset = 'default';
	}
	root.className = 'hesabix-chat-root hesabix-chat--theme-' + ( cfg.theme === 'dark' ? 'dark' : 'light' ) + ' hesabix-chat--preset-' + uiPreset;
	root.setAttribute( 'dir', cfg.dir || 'rtl' );
	root.style.setProperty( '--hesabix-btn', cfg.buttonColor );
	root.style.setProperty( '--hesabix-btn-txt', cfg.buttonTextColor );
	root.style.setProperty( '--hesabix-panel-w', ( cfg.panelWidth || 380 ) + 'px' );
	root.style.setProperty( '--hesabix-panel-h', ( cfg.panelHeight || 520 ) + 'px' );
	root.style.setProperty( '--hesabix-z', String( cfg.zIndex || 99999 ) );
	root.style.setProperty( '--hesabix-bottom', ( cfg.offsetBottom || 24 ) + 'px' );
	root.style.setProperty( '--hesabix-side', ( cfg.offsetSide || 24 ) + 'px' );
	root.style.setProperty( '--hesabix-radius', ( cfg.borderRadius || 12 ) + 'px' );
	root.style.setProperty( '--hesabix-accent', cfg.buttonColor );

	var pos = posClass( cfg.buttonPosition );

	var wrap = document.createElement( 'div' );
	wrap.className = 'hesabix-chat-floating ' + pos;

	var btn = document.createElement( 'button' );
	btn.type = 'button';
	btn.className = 'hesabix-chat-launcher';
	btn.setAttribute( 'aria-expanded', 'false' );
	btn.setAttribute( 'aria-haspopup', 'dialog' );
	btn.style.backgroundColor = cfg.buttonColor;
	btn.style.color = cfg.buttonTextColor;
	btn.insertAdjacentHTML(
		'afterbegin',
		'<span class="hesabix-chat-launcher-ico" aria-hidden="true"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M4 4h11a3 3 0 0 1 3 3v5a3 3 0 0 1-3 3H8l-4 3.5V7a3 3 0 0 1 3-3Z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M8 8.5h7M8 12h4.5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg></span>'
	);
	var launcherLab = document.createElement( 'span' );
	launcherLab.className = 'hesabix-chat-launcher-txt';
	launcherLab.textContent = cfg.buttonText;
	btn.appendChild( launcherLab );

	var panel = document.createElement( 'div' );
	panel.className = 'hesabix-chat-panel hesabix-chat--hidden ' + pos;
	panel.setAttribute( 'role', 'dialog' );
	panel.setAttribute( 'aria-modal', 'true' );
	panel.setAttribute( 'aria-label', cfg.chatTitle );

	var surface = document.createElement( 'div' );
	surface.className = 'hesabix-chat-surface hesabix-chat-surface--' + uiPreset;

	var header = document.createElement( 'div' );
	header.className = 'hesabix-chat-header';
	var htitle = document.createElement( 'h2' );
	htitle.textContent = cfg.chatTitle;
	var hBrand = document.createElement( 'div' );
	hBrand.className = 'hesabix-chat-header-brand';
	if ( cfg.headerLogoUrl && cfg.headerLogoUrl.toString().length ) {
		var hImg = document.createElement( 'img' );
		hImg.className = 'hesabix-chat-header-logo';
		hImg.src = cfg.headerLogoUrl;
		hImg.alt = '';
		hImg.setAttribute( 'width', '36' );
		hImg.setAttribute( 'height', '36' );
		hImg.decoding = 'async';
		hImg.loading = 'lazy';
		hBrand.appendChild( hImg );
	}
	hBrand.appendChild( htitle );
	var hact = document.createElement( 'div' );
	hact.className = 'hesabix-chat-header-actions';
	var wsConnLabel = document.createElement( 'span' );
	wsConnLabel.className = 'hesabix-chat-ws-conn';
	wsConnLabel.setAttribute( 'role', 'status' );
	var btnNew = document.createElement( 'button' );
	btnNew.type = 'button';
	btnNew.textContent = cfg.strings.back;
	btnNew.title = cfg.strings.newChatHint;
	var btnClose = document.createElement( 'button' );
	btnClose.type = 'button';
	btnClose.textContent = cfg.strings.close;
	hact.appendChild( wsConnLabel );
	hact.appendChild( btnNew );
	hact.appendChild( btnClose );
	header.appendChild( hBrand );
	header.appendChild( hact );

	var msgBox = document.createElement( 'div' );
	msgBox.className = 'hesabix-chat-messages';

	function esc( t ) {
		var d = document.createElement( 'div' );
		d.textContent = t;
		return d.innerHTML;
	}

	var formEl = document.createElement( 'form' );
	formEl.className = 'hesabix-chat-form';
	var emailMode = ( cfg.emailField || 'required' ).toString();
	var showPageCtx = cfg.showPageContext === true || cfg.showPageContext === 1 || cfg.showPageContext === '1';
	var pageTitle = ( typeof document !== 'undefined' && document.title ) ? document.title : '';
	var pageHref = ( typeof window !== 'undefined' && window.location && window.location.href ) ? window.location.href : '';
	var pageCtxBlock = '';
	if ( showPageCtx ) {
		pageCtxBlock =
			'<div class="hesabix-chat-page-ctx" role="note">' +
			'<div class="hesabix-chat-page-ctx-row"><span class="hesabix-chat-page-ctx-l">' + esc( ( cfg.strings && cfg.strings.pageContextLabel ) || '' ) + ': </span>' +
			'<a class="hesabix-chat-page-ctx-a" href="' + esc( pageHref ) + '" target="_blank" rel="noopener noreferrer">' + esc( pageTitle || pageHref ) + '</a></div>' +
			'<div class="hesabix-chat-page-ctx-url" title="' + esc( pageHref ) + '">' + esc( pageHref ) + '</div></div>';
	}
	var emailPart = '';
	if ( emailMode === 'hidden' ) {
		emailPart = '<input type="hidden" name="email" value="" />';
	} else {
		var emReq = ( emailMode === 'required' ) ? ' required' : '';
		var emHint = '';
		if ( emailMode === 'optional' && cfg.strings && cfg.strings.emailOptionalHint ) {
			emHint = '<p class="hesabix-chat-fld-hint hesabix-chat-fld-hint--email">' + esc( cfg.strings.emailOptionalHint ) + '</p>';
		}
		emailPart =
			'<label class="hesabix-chat-fld"><span class="hesabix-chat-fld-l">' + esc( cfg.strings.email ) + '</span>' +
			'<input type="email" name="email" autocomplete="email"' + emReq + ' /></label>' + emHint;
	}
	formEl.innerHTML =
		'<div class="hesabix-chat-form-lead"><h3 class="hesabix-chat-form-title">' + esc( cfg.strings.formTitle || '' ) + '</h3>' +
		'<p class="hesabix-chat-form-hint">' + esc( cfg.strings.formSubtitle || '' ) + '</p></div>' +
		pageCtxBlock +
		'<div class="hesabix-chat-error hesabix-chat--hidden" data-err></div>' +
		'<div class="hesabix-chat-form-fields">' +
		'<label class="hesabix-chat-fld"><span class="hesabix-chat-fld-l">' + esc( cfg.strings.firstName ) + '</span><input type="text" name="first_name" required autocomplete="given-name" /></label>' +
		'<label class="hesabix-chat-fld"><span class="hesabix-chat-fld-l">' + esc( cfg.strings.lastName ) + '</span><input type="text" name="last_name" required autocomplete="family-name" /></label>' +
		emailPart +
		'<label class="hesabix-chat-fld"><span class="hesabix-chat-fld-l">' + esc( cfg.strings.phone ) + '</span><input type="tel" name="phone" required autocomplete="tel" /></label></div>' +
		'<button type="submit" class="hesabix-chat-form-submit">' + esc( cfg.strings.start ) + '</button>';

	var comp = document.createElement( 'div' );
	comp.className = 'hesabix-chat-composer hesabix-chat--hidden';
	var errC = document.createElement( 'div' );
	errC.className = 'hesabix-chat-error hesabix-chat--hidden';
	var row = document.createElement( 'div' );
	row.className = 'hesabix-chat-composer-row';
	var ta = document.createElement( 'textarea' );
	ta.rows = 2;
	ta.placeholder = cfg.strings.placeholder;
	var sendBtn = document.createElement( 'button' );
	sendBtn.type = 'button';
	sendBtn.className = 'hesabix-chat-send';
	sendBtn.textContent = cfg.strings.send;
	row.appendChild( ta );
	row.appendChild( sendBtn );
	comp.appendChild( errC );
	comp.appendChild( row );

	var peerTypingEl = document.createElement( 'div' );
	peerTypingEl.className = 'hesabix-chat-peer-typing hesabix-chat--hidden';
	peerTypingEl.setAttribute( 'role', 'status' );
	peerTypingEl.setAttribute( 'aria-live', 'polite' );

	surface.appendChild( header );
	surface.appendChild( formEl );
	surface.appendChild( msgBox );
	surface.appendChild( peerTypingEl );
	surface.appendChild( comp );
	panel.appendChild( surface );
	surface.classList.add( 'hesabix-chat--step-form' );
	wrap.appendChild( btn );
	wrap.appendChild( panel );
	/* پرتال پنل: در حالت global دکمه fixed است و پنل absolute نسبت به host با ارتفاع صفر اشتباه جا می‌گرفت؛ پنل در body. */
	{
		var hesabixChatVars = [ '--hesabix-btn', '--hesabix-btn-txt', '--hesabix-panel-w', '--hesabix-panel-h', '--hesabix-z', '--hesabix-bottom', '--hesabix-side', '--hesabix-radius', '--hesabix-accent' ];
		for ( var vi = 0; vi < hesabixChatVars.length; vi++ ) {
			var vnm = hesabixChatVars[ vi ];
			panel.style.setProperty( vnm, root.style.getPropertyValue( vnm ) );
		}
		panel.setAttribute( 'dir', root.getAttribute( 'dir' ) || 'rtl' );
		panel.classList.add(
			cfg.theme === 'dark' ? 'hesabix-chat--theme-dark' : 'hesabix-chat--theme-light',
			'hesabix-chat--preset-' + uiPreset,
			'hesabix-chat-panel--portaled'
		);
		wrap.removeChild( panel );
		document.body.appendChild( panel );
	}
	root.appendChild( wrap );
	host.appendChild( root );

	function setupVisitorFileUpload() {
		if ( ! cfg.showFileUpload ) {
			return;
		}
		var base = ( cfg.apiBase || '' ).replace( /\/$/, '' );
		if ( ! base || ! cfg.publicKey ) {
			return;
		}
		var optUrl = base + '/api/v1/public/crm-chat/widget-options?public_key=' + encodeURIComponent( cfg.publicKey );
		fetch( optUrl, { method: 'GET', credentials: 'omit' } )
			.then( function ( res ) {
				return res.text().then( function ( t ) {
					return { ok: res.ok, t: t };
				} );
			} )
			.then( function ( pack ) {
				var j = parseJsonSafe( pack.t );
				if ( ! pack.ok || ! j ) {
					return;
				}
				var wrapD = j.data !== undefined && j.data !== null ? j.data : j;
				if ( ! wrapD || ! wrapD.allow_file_upload ) {
					return;
				}
				var fileRow = document.createElement( 'div' );
				fileRow.className = 'hesabix-chat-file-row';
				var finp = document.createElement( 'input' );
				finp.type = 'file';
				finp.className = 'hesabix-chat-attach';
				finp.setAttribute( 'aria-label', ( cfg.strings && cfg.strings.attach ) || '' );
				fileRow.appendChild( finp );
				comp.appendChild( fileRow );
				finp.addEventListener( 'change', function ( ev ) {
					var f = ev.target && ev.target.files && ev.target.files[0];
					if ( ! f || ! state.session ) {
						return;
					}
					showFormError( errC, '' );
					postFile( state.session.conversation_id, state.session.visitor_token, f, '' )
						.then( function () {
							ev.target.value = '';
							return refreshMessages();
						} )
						.catch( function ( e ) {
							showFormError( errC, e.message || cfg.strings.errorGeneric );
						} );
				} );
			} )
			.catch( function () {} );
	}
	setupVisitorFileUpload();

	chatLog( 'DOM آماده', {
		hostId: host.id,
		hostClass: host.className,
		shortcode: host.classList.contains( 'hesabix-chat-host--shortcode' ),
		portaled: panel.classList.contains( 'hesabix-chat-panel--portaled' ),
		panelParent: panel.parentNode && panel.parentNode.nodeName
	} );
	chatLogV( 'نمونه', {
		panelRect: ( typeof panel.getBoundingClientRect === 'function' ) ? panel.getBoundingClientRect() : null,
		launcherInDom: document.body.contains( btn )
	} );
	} catch ( initEx ) {
		chatWarn( 'خطا حین ساخت ویجت (قبل از اتصال رویدادها)', ( initEx && initEx.message ) || initEx, initEx );
		return;
	}

	function showFormError( el, msg ) {
		if ( ! el ) {
			return;
		}
		if ( msg ) {
			el.textContent = msg;
			el.classList.remove( 'hesabix-chat--hidden' );
		} else {
			el.textContent = '';
			el.classList.add( 'hesabix-chat--hidden' );
		}
	}

	function updateWsConn( code ) {
		var s = ( cfg.strings && cfg.strings ) || {};
		var isRtl = ( ( cfg.dir || 'rtl' ) + '' ) === 'rtl';
		if ( ! wsConnLabel ) {
			return;
		}
		if ( code === 'connecting' ) {
			wsConnLabel.className = 'hesabix-chat-ws-conn hesabix-chat-ws-conn--connecting';
			wsConnLabel.textContent = s.wsConnecting || ( isRtl ? 'در حال اتصال…' : 'Connecting…' );
			wsConnLabel.title = wsConnLabel.textContent;
		} else if ( code === 'live' ) {
			wsConnLabel.className = 'hesabix-chat-ws-conn hesabix-chat-ws-conn--live';
			wsConnLabel.textContent = s.wsLive || ( isRtl ? 'زنده' : 'Live' );
			wsConnLabel.title = s.wsLiveHint || s.wsLive || ( isRtl ? 'اتصال بلادرنگ برقرار است' : 'Real-time link active' );
		} else {
			wsConnLabel.className = 'hesabix-chat-ws-conn hesabix-chat-ws-conn--offline';
			wsConnLabel.textContent = s.wsOffline || ( isRtl ? 'غیرزنده' : 'Offline' );
			wsConnLabel.title = s.wsOfflineHint || s.wsOffline || ( isRtl ? 'فقط وقفهٔ اعلان؛ پیام هنوز ارسال می‌شود' : 'Polling; messages still work' );
		}
	}

	function updatePeerTypingUI() {
		var s2 = ( cfg.strings && cfg.strings ) || {};
		var isRtl2 = ( ( cfg.dir || 'rtl' ) + '' ) === 'rtl';
		var t = s2.agentTyping || ( isRtl2 ? 'پشتیبان در حال تایپ…' : 'Support is typing…' );
		if ( state.agentTyping && peerTypingEl && t ) {
			peerTypingEl.textContent = t;
			peerTypingEl.classList.remove( 'hesabix-chat--hidden' );
		} else if ( peerTypingEl ) {
			peerTypingEl.classList.add( 'hesabix-chat--hidden' );
		}
	}

	function applyMessagesReadFromEvent( msg ) {
		if ( ! state.session || ! msg || +msg.conversation_id !== +state.session.conversation_id ) {
			return;
		}
		var ids = msg.message_ids;
		var at = msg.read_at;
		if ( ! ids || ! ids.length ) {
			return;
		}
		var idset = {};
		ids.forEach( function ( id ) {
			if ( id != null ) {
				idset[ id ] = 1;
			}
		} );
		var changed = false;
		state.messages.forEach( function ( m ) {
			if ( m && m.id != null && idset[ m.id ] && at != null && at !== '' ) {
				m.read_at = at;
				changed = true;
			}
		} );
		if ( changed ) {
			renderMessages();
		}
	}

	function sendVisitorTyping( active ) {
		if ( ! state.ws || state.ws.readyState !== 1 ) {
			return;
		}
		try {
			state.ws.send( JSON.stringify( { type: 'typing', active: Boolean( active ) } ) );
		} catch ( e0 ) {}
	}

	function scheduleVisitorTypingStop() {
		if ( state.visitorTypingStopTimer ) {
			clearTimeout( state.visitorTypingStopTimer );
		}
		state.visitorTypingStopTimer = setTimeout( function () {
			state.visitorTypingStopTimer = null;
			sendVisitorTyping( false );
		}, 800 );
	}

	function disconnectWs() {
		if ( state.agentTypingTimer ) {
			clearTimeout( state.agentTypingTimer );
			state.agentTypingTimer = null;
		}
		try {
			if ( state.ws ) {
				state.ws.close();
			}
		} catch ( e1 ) {}
		state.ws = null;
	}

	function connectWs( convId, token ) {
		disconnectWs();
		updateWsConn( 'connecting' );
		var u = getWsUrl();
		if ( ! u ) {
			chatLogV( 'WebSocket: آدرس خالی (apiBase / پروتکل؟)' );
			updateWsConn( 'offline' );
			return;
		}
		var ws;
		try {
			ws = new WebSocket( u );
		} catch ( e2 ) {
			chatLogV( 'WebSocket: ساخت ناموفق', u, e2 );
			updateWsConn( 'offline' );
			return;
		}
		chatLogV( 'WebSocket: اتصال', u );
		state.ws = ws;
		ws.onopen = function () {
			ws.send(
				JSON.stringify( {
					type: 'auth',
					role: 'visitor',
					visitor_token: token,
					conversation_id: convId
				} )
			);
		};
		ws.onmessage = function ( ev ) {
			var msg = parseJsonSafe( ev.data );
			if ( ! msg ) {
				return;
			}
			if ( msg.type === 'auth_ok' ) {
				updateWsConn( 'live' );
				return;
			}
			if ( msg.type === 'crm_chat.event' && msg.event === 'message.created' ) {
				refreshMessages().catch( function () {} );
				return;
			}
			if ( msg.type === 'crm_chat.event' && msg.event === 'messages.read' ) {
				applyMessagesReadFromEvent( msg );
				return;
			}
			if ( msg.type === 'crm_chat.event' && msg.event === 'typing' ) {
				if ( +msg.conversation_id === +convId && ( ( msg.from_role || '' ) + '' ) === 'agent' ) {
					if ( state.agentTypingTimer ) {
						clearTimeout( state.agentTypingTimer );
						state.agentTypingTimer = null;
					}
					state.agentTyping = Boolean( msg.active );
					updatePeerTypingUI();
					if ( state.agentTyping ) {
						state.agentTypingTimer = setTimeout( function () {
							state.agentTypingTimer = null;
							state.agentTyping = false;
							updatePeerTypingUI();
						}, 4000 );
					}
				}
				return;
			}
		};
		ws.onerror = function () {
			updateWsConn( 'offline' );
		};
		ws.onclose = function () {
			if ( state.ws === ws ) {
				state.ws = null;
			}
			updateWsConn( 'offline' );
		};
	}

	function renderMessages() {
		msgBox.innerHTML = '';
		if ( ! state.session ) {
			return;
		}
		var sUi = ( cfg.strings && cfg.strings ) || {};
		var isRtl3 = ( ( cfg.dir || 'rtl' ) + '' ) === 'rtl';
		var wmsg = ( cfg.welcomeMessage && cfg.welcomeMessage.toString() ) || '';
		wmsg = wmsg.replace( /^\s+|\s+$/g, '' );
		if ( wmsg ) {
			var wel = document.createElement( 'div' );
			wel.className = 'hesabix-chat-welcome';
			var wlab = document.createElement( 'div' );
			wlab.className = 'hesabix-chat-welcome-kicker';
			wlab.textContent = cfg.chatTitle || cfg.strings.support;
			var wbody = document.createElement( 'div' );
			wbody.className = 'hesabix-chat-welcome-text';
			wmsg.split( /\r?\n/ ).forEach( function ( line ) {
				var p = document.createElement( 'p' );
				p.textContent = line;
				wbody.appendChild( p );
			} );
			var wic = document.createElement( 'div' );
			wic.className = 'hesabix-chat-welcome-ico';
			wic.setAttribute( 'aria-hidden', 'true' );
			wic.innerHTML =
				'<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M7 3h6a3 3 0 0 1 2.2 1l2 2.2A3 3 0 0 1 18 7.7V19a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z" stroke="currentColor" stroke-width="1.3" fill="currentColor" fill-opacity="0.1"/><path d="M8.5 8.5H13M8.5 12h3.5" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>';
			wel.appendChild( wic );
			var wmain = document.createElement( 'div' );
			wmain.className = 'hesabix-chat-welcome-main';
			wmain.appendChild( wlab );
			wmain.appendChild( wbody );
			wel.appendChild( wmain );
			msgBox.appendChild( wel );
		}
		var rtt = ( cfg.responseTimeText && cfg.responseTimeText.toString() ) || '';
		rtt = rtt.replace( /^\s+|\s+$/g, '' );
		if ( rtt ) {
			var eta = document.createElement( 'div' );
			eta.className = 'hesabix-chat-response-eta';
			eta.setAttribute( 'role', 'status' );
			var etIco = document.createElement( 'span' );
			etIco.className = 'hesabix-chat-response-eta-ico';
			etIco.setAttribute( 'aria-hidden', 'true' );
			etIco.innerHTML =
				'<svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2.5"/></svg>';
			var etx = document.createElement( 'span' );
			etx.className = 'hesabix-chat-response-eta-txt';
			etx.textContent = rtt;
			eta.appendChild( etIco );
			eta.appendChild( etx );
			msgBox.appendChild( eta );
		}
		state.messages.forEach( function ( m ) {
			var role = ( m.sender_role || '' ).toString();
			var div = document.createElement( 'div' );
			div.className = 'hesabix-chat-bubble hesabix-chat-bubble--' + ( role === 'visitor' ? 'visitor' : 'agent' );
			var label = role === 'visitor' ? cfg.strings.you : cfg.strings.support;
			var strong = document.createElement( 'strong' );
			strong.textContent = label;
			var bodyP = document.createElement( 'div' );
			bodyP.textContent = ( m.body || '' ).toString();
			if ( m.file && m.file.original_name && m.file.id ) {
				var fileDiv = document.createElement( 'div' );
				fileDiv.className = 'hesabix-chat-file';
				var dlBtn = document.createElement( 'button' );
				dlBtn.type = 'button';
				dlBtn.className = 'hesabix-chat-file-dl';
				dlBtn.textContent = m.file.original_name;
				dlBtn.addEventListener( 'click', function () {
					if ( ! state.session ) {
						return;
					}
					downloadVisitorFile(
						state.session.conversation_id,
						state.session.visitor_token,
						m.file.id,
						m.file.original_name
					).catch( function ( e ) {
						showFormError( errC, e.message || cfg.strings.errorGeneric );
					} );
				} );
				fileDiv.appendChild( dlBtn );
				bodyP.appendChild( fileDiv );
			}
			var small = document.createElement( 'small' );
			small.className = 'hesabix-chat-msg-time';
			small.textContent = formatTime( m.created_at );
			var meta = document.createElement( 'div' );
			meta.className =
				'hesabix-chat-bubble-meta' +
				( role === 'visitor' ? ' hesabix-chat-bubble-meta--visitor' : ' hesabix-chat-bubble-meta--agent' );
			if ( role === 'visitor' ) {
				var readBy = m.read_at;
				var tSent = sUi.msgDelivered || ( isRtl3 ? 'ارسال شد' : 'Sent' );
				var tRead = sUi.msgReadBySupport || ( isRtl3 ? 'پشتیبان خواند' : 'Read by support' );
				var receipt = document.createElement( 'span' );
				receipt.className = 'hesabix-chat-msg-receipt' + ( readBy ? ' hesabix-chat-msg-receipt--read' : '' );
				receipt.setAttribute( 'title', readBy ? tRead : tSent );
				receipt.setAttribute( 'aria-label', readBy ? tRead : tSent );
				receipt.innerHTML =
					'<svg class="hesabix-chat-tick-ico" width="20" height="12" viewBox="0 0 28 12" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false">' +
					'<path d="M1 6.2l2.3 2.2L7.8 2" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" class="hesabix-chat-tick-1st"/>' +
					'<path d="M6.5 6.2l2.3 2.2L13.2 2" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" class="hesabix-chat-tick-2nd"/>' +
					'</svg>';
				meta.appendChild( receipt );
			}
			meta.appendChild( small );
			div.appendChild( strong );
			div.appendChild( bodyP );
			div.appendChild( meta );
			msgBox.appendChild( div );
		} );
		msgBox.scrollTop = msgBox.scrollHeight;
	}

	function refreshMessages() {
		if ( ! state.session ) {
			return;
		}
		return listMessages( state.session.conversation_id, state.session.visitor_token, 100 ).then( function ( items ) {
			state.messages = items;
			renderMessages();
			syncMarkAgentRead( items );
		} );
	}

	function enterChatMode() {
		formEl.classList.add( 'hesabix-chat--hidden' );
		comp.classList.remove( 'hesabix-chat--hidden' );
		surface.classList.remove( 'hesabix-chat--step-form' );
		surface.classList.add( 'hesabix-chat--step-chat' );
		if ( wsConnLabel ) {
			updateWsConn( 'offline' );
		}
	}

	function enterFormMode() {
		state.messages = [];
		msgBox.innerHTML = '';
		formEl.classList.remove( 'hesabix-chat--hidden' );
		comp.classList.add( 'hesabix-chat--hidden' );
		surface.classList.remove( 'hesabix-chat--step-chat' );
		surface.classList.add( 'hesabix-chat--step-form' );
		if ( wsConnLabel ) {
			wsConnLabel.textContent = '';
			wsConnLabel.className = 'hesabix-chat-ws-conn';
			wsConnLabel.title = '';
		}
		unbindRealtime();
	}

	function bindRealtime() {
		if ( ! state.session || ! state.open ) {
			chatLogV( 'bindRealtime: رد (session/open)', { hasSession: Boolean( state.session ), open: state.open } );
			return;
		}
		var cid = state.session.conversation_id;
		var tok = state.session.visitor_token;
		chatLogV( 'bindRealtime: شروع', { conversation: cid } );
		connectWs( cid, tok );
		startPoll( cid, tok );
	}

	function unbindRealtime() {
		if ( state.visitorTypingStopTimer ) {
			clearTimeout( state.visitorTypingStopTimer );
			state.visitorTypingStopTimer = null;
		}
		sendVisitorTyping( false );
		state.agentTyping = false;
		if ( state.agentTypingTimer ) {
			clearTimeout( state.agentTypingTimer );
			state.agentTypingTimer = null;
		}
		if ( peerTypingEl ) {
			peerTypingEl.classList.add( 'hesabix-chat--hidden' );
		}
		disconnectWs();
		stopPoll();
	}

	function afterSessionReady( skipRealtime ) {
		enterChatMode();
		return refreshMessages().then( function () {
			if ( ! skipRealtime && state.open ) {
				bindRealtime();
			}
		} );
	}

	var pf = cfg.prefill || {};
	if ( pf.first_name ) {
		formEl.querySelector( '[name="first_name"]' ).value = pf.first_name;
	}
	if ( pf.last_name ) {
		formEl.querySelector( '[name="last_name"]' ).value = pf.last_name;
	}
	if ( pf.email ) {
		var preEl = formEl.querySelector( '[name="email"]' );
		if ( preEl ) {
			preEl.value = pf.email;
		}
	}

	var existing = loadSession();
	if ( existing ) {
		state.session = {
			conversation_id: existing.conversation_id,
			visitor_token: existing.visitor_token
		};
		enterChatMode();
		afterSessionReady( true )
			.then( function () {} )
			.catch( function ( se ) {
				chatLogV( 'بازیابی نشست محلی ناموفق', se );
				clearSession();
				state.session = null;
				enterFormMode();
			} );
	}

	formEl.addEventListener( 'submit', function ( ev ) {
		ev.preventDefault();
		var fd = new FormData( formEl );
		var errEl = formEl.querySelector( '[data-err]' );
		showFormError( errEl, '' );
		startConversation( {
			first_name: ( fd.get( 'first_name' ) || '' ).toString().trim(),
			last_name: ( fd.get( 'last_name' ) || '' ).toString().trim(),
			email: ( fd.get( 'email' ) || '' ).toString().trim(),
			phone: ( fd.get( 'phone' ) || '' ).toString().trim()
		} )
			.then( function ( data ) {
				var cid = data.conversation_id;
				var tok = data.visitor_token;
				if ( ! cid || ! tok ) {
					throw new Error( cfg.strings.errorGeneric );
				}
				saveSession( cid, tok );
				state.session = { conversation_id: cid, visitor_token: tok };
				return afterSessionReady( false );
			} )
			.catch( function ( e ) {
				chatLogV( 'startConversation خطا', e && e.message, e );
				showFormError( errEl, e.message || cfg.strings.errorGeneric );
			} );
	} );

	sendBtn.addEventListener( 'click', function () {
		if ( ! state.session ) {
			return;
		}
		var t = ( ta.value || '' ).trim();
		showFormError( errC, '' );
		if ( ! t ) {
			return;
		}
		postMessage( state.session.conversation_id, state.session.visitor_token, t )
			.then( function () {
				ta.value = '';
				if ( state.visitorTypingStopTimer ) {
					clearTimeout( state.visitorTypingStopTimer );
					state.visitorTypingStopTimer = null;
				}
				sendVisitorTyping( false );
				return refreshMessages();
			} )
			.catch( function ( e ) {
				showFormError( errC, e.message || cfg.strings.errorGeneric );
			} );
	} );

	ta.addEventListener( 'input', function () {
		if ( ! state.session ) {
			return;
		}
		var v = ( ta.value || '' );
		if ( ! v.length ) {
			if ( state.visitorTypingStopTimer ) {
				clearTimeout( state.visitorTypingStopTimer );
				state.visitorTypingStopTimer = null;
			}
			sendVisitorTyping( false );
			return;
		}
		sendVisitorTyping( true );
		scheduleVisitorTypingStop();
	} );
	ta.addEventListener( 'blur', function () {
		if ( state.visitorTypingStopTimer ) {
			clearTimeout( state.visitorTypingStopTimer );
			state.visitorTypingStopTimer = null;
		}
		sendVisitorTyping( false );
	} );

	btnNew.addEventListener( 'click', function () {
		if ( ! window.confirm( cfg.strings.newChatHint ) ) {
			return;
		}
		clearSession();
		state.session = null;
		enterFormMode();
	} );

	function setOpen( v ) {
		state.open = v;
		btn.setAttribute( 'aria-expanded', v ? 'true' : 'false' );
		if ( v ) {
			panel.classList.remove( 'hesabix-chat--hidden' );
			( function () {
				var st = ( typeof getComputedStyle === 'function' ) ? getComputedStyle( panel ) : null;
				var r = ( typeof panel.getBoundingClientRect === 'function' ) ? panel.getBoundingClientRect() : null;
				chatLog( 'پنل باز', {
					hasSession: Boolean( state.session ),
					className: panel.className,
					rect: r ? { w: r.width, h: r.height, top: r.top, left: r.left } : null,
					css: st ? { zIndex: st.zIndex, display: st.display, visibility: st.visibility, opacity: st.opacity, pointerEvents: st.pointerEvents } : null
				} );
			} )();
			if ( state.session ) {
				refreshMessages()
					.then( function () {
						bindRealtime();
					} )
					.catch( function () {} );
			}
		} else {
			panel.classList.add( 'hesabix-chat--hidden' );
			chatLogV( 'پنل بسته' );
			unbindRealtime();
		}
	}

	btn.addEventListener( 'click', function ( ev ) {
		chatLog( 'کلیک لانچر', { wasOpen: state.open, target: ev.target && ev.target.nodeName } );
		setOpen( ! state.open );
	} );

	btnClose.addEventListener( 'click', function () {
		setOpen( false );
	} );

	document.addEventListener( 'keydown', function ( e ) {
		if ( e.key === 'Escape' && state.open ) {
			setOpen( false );
		}
	} );
} )();
