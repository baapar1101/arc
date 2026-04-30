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

	function remembersPanelAcrossPages() {
		var r = cfg.rememberPanelBetweenPages;
		if ( typeof r === 'undefined' ) {
			return true;
		}
		return r === true || r === 1 || r === '1';
	}

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

	chatLogV( 'راه\u200cاندازی', {
		loadMode: cfg.loadMode,
		hasApiBase: Boolean( cfg.apiBase && String( cfg.apiBase ).length ),
		hasPublicKey: Boolean( cfg.publicKey && String( cfg.publicKey ).length ),
		rememberPanel: remembersPanelAcrossPages(),
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

	function panelUiStorageKey() {
		return 'hesabix_wp_panel_' + STORAGE_VERSION + '_' + simpleKey( cfg.apiBase + '|' + cfg.publicKey );
	}

	function readRememberedPanelOpen() {
		if ( ! remembersPanelAcrossPages() ) {
			return null;
		}
		try {
			if ( typeof sessionStorage === 'undefined' ) {
				return null;
			}
			var raw = sessionStorage.getItem( panelUiStorageKey() );
			if ( raw === null || raw === '' ) {
				return null;
			}
			if ( raw === '1' ) {
				return true;
			}
			if ( raw === '0' ) {
				return false;
			}
		} catch ( ePan ) {}
		return null;
	}

	function persistRememberedPanelOpen( opened ) {
		if ( ! remembersPanelAcrossPages() ) {
			return;
		}
		try {
			if ( typeof sessionStorage === 'undefined' ) {
				return;
			}
			sessionStorage.setItem( panelUiStorageKey(), opened ? '1' : '0' );
		} catch ( ePan2 ) {}
	}

	function clearRememberedPanelOpen() {
		try {
			if ( typeof sessionStorage !== 'undefined' ) {
				sessionStorage.removeItem( panelUiStorageKey() );
			}
		} catch ( ePan3 ) {}
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
		clearRememberedPanelOpen();
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

	function patchVisitorCurrentPage( convId, token, pageUrl ) {
		var path = '/api/v1/public/crm-chat/conversations/' + encodeURIComponent( convId ) + '/current-page';
		return apiFetch( apiPath( path ), {
			method: 'PATCH',
			headers: Object.assign( { 'Content-Type': 'application/json' }, visitorTokenHeaders( token ) ),
			body: JSON.stringify( { page_url: pageUrl } )
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

	function playAgentReplySound() {
		var url = ( cfg.agentReplySoundUrl || '' ).toString();
		if ( ! url ) {
			return;
		}
		try {
			var a = new Audio( url );
			a.volume = 0.85;
			var p = a.play();
			if ( p && typeof p.catch === 'function' ) {
				p.catch( function () {} );
			}
		} catch ( ePlay ) {}
	}

	function primeAgentSoundForAutoplay() {
		var url = ( cfg.agentReplySoundUrl || '' ).toString();
		if ( ! url ) {
			return;
		}
		try {
			var a = new Audio( url );
			a.volume = 0.001;
			var p = a.play();
			if ( p && typeof p.catch === 'function' ) {
				p.catch( function () {} );
			}
		} catch ( eIgn ) {}
	}

	function maybePlayAgentReplySound( items ) {
		var maxId = maxAgentMessageId( items );
		var url = ( cfg.agentReplySoundUrl || '' ).toString();
		if ( ! state.agentSoundPrimed ) {
			state.lastAgentMsgNotifiedId = maxId;
			state.agentSoundPrimed = true;
			return;
		}
		if ( maxId > state.lastAgentMsgNotifiedId ) {
			state.lastAgentMsgNotifiedId = maxId;
			if ( url ) {
				playAgentReplySound();
			}
		}
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

	function visitorFileDownloadUrl( conversationId, fileId ) {
		return apiPath( '/api/v1/public/crm-chat/conversations/' + conversationId + '/files/' + encodeURIComponent( fileId ) + '/download' );
	}

	/** دانلود فایل ضمیمه بدون گذاشتن توکن در URL (هدر X-Visitor-Token). */
	function downloadVisitorFile( convId, token, fileId, displayName ) {
		var u = visitorFileDownloadUrl( convId, fileId );
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
		localCannedAfterVisitor: [],
		agentSoundPrimed: false,
		lastAgentMsgNotifiedId: 0,
		ws: null,
		pollTimer: null,
		usePoll: false,
		agentTyping: false,
		agentTypingTimer: null,
		agentTypingName: '',
		seenAgentJoinIds: {},
		agentJoinBannerText: '',
		visitorTypingSendTimer: null,
		visitorTypingStopTimer: null,
		pageUrlReportTimer: null,
		visitorOpts: { allowFile: false, allowVoice: false }
	};

	/** همگام‌سازی نشانی صفحهٔ فعلی با سرور (SPA: pushState/popstate/hashchange + interval). */
	var visitorPageUrlHook = {
		installed: false,
		lastSent: '',
		interval: null,
		pushState: null,
		replaceState: null
	};

	function scheduleVisitorPageUrlReport() {
		if ( state.pageUrlReportTimer ) {
			clearTimeout( state.pageUrlReportTimer );
		}
		state.pageUrlReportTimer = setTimeout( function () {
			state.pageUrlReportTimer = null;
			reportVisitorPageUrlIfChanged();
		}, 380 );
	}

	function reportVisitorPageUrlIfChanged() {
		if ( ! state.session || typeof window === 'undefined' || typeof location === 'undefined' ) {
			return;
		}
		var href = String( location.href || '' );
		if ( ! href || href === visitorPageUrlHook.lastSent ) {
			return;
		}
		visitorPageUrlHook.lastSent = href;
		var cid = state.session.conversation_id;
		var tok = state.session.visitor_token;
		patchVisitorCurrentPage( cid, tok, href ).catch( function ( e ) {
			visitorPageUrlHook.lastSent = '';
			chatLogV( 'current-page PATCH', e && e.message );
		} );
	}

	function installVisitorPageUrlTracking() {
		if ( typeof window === 'undefined' ) {
			return;
		}
		if ( ! visitorPageUrlHook.installed ) {
			window.addEventListener( 'popstate', scheduleVisitorPageUrlReport );
			window.addEventListener( 'hashchange', scheduleVisitorPageUrlReport );
			visitorPageUrlHook.pushState = history.pushState;
			visitorPageUrlHook.replaceState = history.replaceState;
			history.pushState = function () {
				var r = visitorPageUrlHook.pushState.apply( history, arguments );
				scheduleVisitorPageUrlReport();
				return r;
			};
			history.replaceState = function () {
				var r = visitorPageUrlHook.replaceState.apply( history, arguments );
				scheduleVisitorPageUrlReport();
				return r;
			};
			visitorPageUrlHook.installed = true;
		}
		visitorPageUrlHook.lastSent = '';
		if ( ! visitorPageUrlHook.interval ) {
			visitorPageUrlHook.interval = window.setInterval( scheduleVisitorPageUrlReport, 3200 );
		}
		scheduleVisitorPageUrlReport();
	}

	function teardownVisitorPageUrlTracking() {
		if ( typeof window === 'undefined' ) {
			return;
		}
		if ( visitorPageUrlHook.interval ) {
			window.clearInterval( visitorPageUrlHook.interval );
			visitorPageUrlHook.interval = null;
		}
		if ( state.pageUrlReportTimer ) {
			clearTimeout( state.pageUrlReportTimer );
			state.pageUrlReportTimer = null;
		}
		if ( visitorPageUrlHook.installed ) {
			window.removeEventListener( 'popstate', scheduleVisitorPageUrlReport );
			window.removeEventListener( 'hashchange', scheduleVisitorPageUrlReport );
			if ( visitorPageUrlHook.pushState ) {
				history.pushState = visitorPageUrlHook.pushState;
				visitorPageUrlHook.pushState = null;
			}
			if ( visitorPageUrlHook.replaceState ) {
				history.replaceState = visitorPageUrlHook.replaceState;
				visitorPageUrlHook.replaceState = null;
			}
			visitorPageUrlHook.installed = false;
		}
		visitorPageUrlHook.lastSent = '';
	}

	var launcherAttentionTimer = null;

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
				maybePlayAgentReplySound( items );
				var prevMax = maxAgentMessageId( state.messages );
				var nextMax = maxAgentMessageId( items );
				var changed = items.length !== state.messages.length || nextMax !== prevMax;
				if ( changed ) {
					state.messages = items;
					renderMessages();
					syncMarkAgentRead( items );
				}
			} ).catch( function () {} );
		}, 4000 );
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
	var themeKey = ( cfg.theme && cfg.theme.toString() ) || 'light';
	var themeClasses;
	if ( themeKey === 'cream' ) {
		themeClasses = [ 'hesabix-chat--theme-light', 'hesabix-chat--theme-cream' ];
	} else if ( themeKey === 'ocean' ) {
		themeClasses = [ 'hesabix-chat--theme-light', 'hesabix-chat--theme-ocean' ];
	} else if ( themeKey === 'midnight' ) {
		themeClasses = [ 'hesabix-chat--theme-dark', 'hesabix-chat--theme-midnight' ];
	} else if ( themeKey === 'dark' ) {
		themeClasses = [ 'hesabix-chat--theme-dark' ];
	} else {
		themeClasses = [ 'hesabix-chat--theme-light' ];
	}
	root.className = 'hesabix-chat-root ' + themeClasses.join( ' ' ) + ' hesabix-chat--preset-' + uiPreset;
	root.setAttribute( 'dir', cfg.dir || 'rtl' );
	root.style.setProperty( '--hesabix-btn', cfg.buttonColor );
	root.style.setProperty( '--hesabix-btn-txt', cfg.buttonTextColor );
	root.style.setProperty( '--hesabix-panel-w', ( cfg.panelWidth || 380 ) + 'px' );
	root.style.setProperty( '--hesabix-panel-h', ( cfg.panelHeight || 520 ) + 'px' );
	root.style.setProperty( '--hesabix-z', String( cfg.zIndex || 99999 ) );
	root.style.setProperty( '--hesabix-bottom', ( cfg.offsetBottom || 24 ) + 'px' );
	var sideDesk = cfg.offsetSideDesktop != null ? cfg.offsetSideDesktop : ( cfg.offsetSide != null ? cfg.offsetSide : 24 );
	var sideMob = cfg.offsetSideMobile != null ? cfg.offsetSideMobile : sideDesk;
	root.style.setProperty( '--hesabix-side', sideDesk + 'px' );
	root.style.setProperty( '--hesabix-side-mobile', sideMob + 'px' );
	root.style.setProperty( '--hesabix-margin-left', ( cfg.marginLeftDesktop || 0 ) + 'px' );
	root.style.setProperty( '--hesabix-margin-right', ( cfg.marginRightDesktop || 0 ) + 'px' );
	root.style.setProperty( '--hesabix-margin-left-mobile', ( cfg.marginLeftMobile || 0 ) + 'px' );
	root.style.setProperty( '--hesabix-margin-right-mobile', ( cfg.marginRightMobile || 0 ) + 'px' );
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
	btnClose.className = 'hesabix-chat-header-close';
	btnClose.setAttribute( 'aria-label', cfg.strings.close || '' );
	btnClose.setAttribute(
		'title',
		( cfg.strings.closeTooltip && String( cfg.strings.closeTooltip ) ) || ( cfg.strings.close || '' )
	);
	btnClose.innerHTML =
		'<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true" focusable="false"><path d="M18 6L6 18M6 6l12 12"/></svg>';
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
	var sendLabel = ( cfg.strings && cfg.strings.send ) ? String( cfg.strings.send ) : '';
	var sendTip = ( cfg.strings && cfg.strings.sendTooltip ) ? String( cfg.strings.sendTooltip ) : sendLabel;
	sendBtn.setAttribute( 'aria-label', sendLabel );
	sendBtn.setAttribute( 'title', sendTip );
	sendBtn.innerHTML =
		'<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' +
		'<line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>';
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
		var hesabixChatVars = [
			'--hesabix-btn', '--hesabix-btn-txt', '--hesabix-panel-w', '--hesabix-panel-h', '--hesabix-z', '--hesabix-bottom',
			'--hesabix-side', '--hesabix-side-mobile', '--hesabix-margin-left', '--hesabix-margin-right',
			'--hesabix-margin-left-mobile', '--hesabix-margin-right-mobile', '--hesabix-radius', '--hesabix-accent'
		];
		for ( var vi = 0; vi < hesabixChatVars.length; vi++ ) {
			var vnm = hesabixChatVars[ vi ];
			panel.style.setProperty( vnm, root.style.getPropertyValue( vnm ) );
		}
		panel.setAttribute( 'dir', root.getAttribute( 'dir' ) || 'rtl' );
		for ( var ti = 0; ti < themeClasses.length; ti++ ) {
			panel.classList.add( themeClasses[ ti ] );
		}
		panel.classList.add( 'hesabix-chat--preset-' + uiPreset, 'hesabix-chat-panel--portaled' );
		wrap.removeChild( panel );
		document.body.appendChild( panel );
	}
	root.appendChild( wrap );
	host.appendChild( root );

	function setupVisitorFileUpload() {
		var wantsFileUi = !!( cfg.showFileUpload );
		var wantsVoiceUi = !!( cfg.showVoiceMessage );
		if ( ! wantsFileUi && ! wantsVoiceUi ) {
			return;
		}
		var base = ( cfg.apiBase || '' ).replace( /\/$/, '' );
		if ( ! base || ! cfg.publicKey ) {
			return;
		}
		var optUrl = base + '/api/v1/public/crm-chat/widget-options?public_key=' + encodeURIComponent( cfg.publicKey );
		var runFetch = function () {
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
				if ( ! wrapD ) {
					return;
				}
				state.visitorOpts.allowFile = !! wrapD.allow_file_upload;
				state.visitorOpts.allowVoice = !! wrapD.allow_voice;
				var effFile = !!( wantsFileUi && state.visitorOpts.allowFile );
				var effVoice = !!( wantsVoiceUi && state.visitorOpts.allowVoice );
				if ( effFile ) {
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
				}
				if ( effVoice ) {
					var micRow = document.createElement( 'div' );
					micRow.className = 'hesabix-chat-voice-row';
					var vin = document.createElement( 'input' );
					vin.type = 'file';
					vin.accept = 'audio/*';
					try {
						vin.capture = 'user';
					} catch ( ig ) {}
					vin.className = 'hesabix-chat-voice-file';
					vin.setAttribute( 'aria-label', ( cfg.strings && cfg.strings.voicePick ) ? String( cfg.strings.voicePick ) : 'Voice' );
					micRow.appendChild( vin );
					comp.appendChild( micRow );
					vin.addEventListener( 'change', function ( ev ) {
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
				}
				if ( effFile || effVoice ) {
					comp.classList.add( 'hesabix-chat-composer--dropzone' );
					if ( ta._hesabixPasteBound !== true ) {
						ta._hesabixPasteBound = true;
						ta.addEventListener( 'paste', function ( pe ) {
							if ( ! effFile || ! state.session ) {
								return;
							}
							var dt = pe.clipboardData || window.clipboardData;
							if ( ! dt || ! dt.files || ! dt.files.length ) {
								return;
							}
							var pf = dt.files[0];
							if ( ! pf ) {
								return;
							}
							pe.preventDefault();
							showFormError( errC, '' );
							postFile( state.session.conversation_id, state.session.visitor_token, pf, '' )
								.then( function () {
									return refreshMessages();
								} )
								.catch( function ( e ) {
									showFormError( errC, e.message || cfg.strings.errorGeneric );
								} );
						} );
						ta.addEventListener( 'dragover', function ( de ) {
							de.preventDefault();
							comp.classList.add( 'hesabix-chat-dragover' );
						} );
						ta.addEventListener( 'dragleave', function () {
							comp.classList.remove( 'hesabix-chat-dragover' );
						} );
						ta.addEventListener( 'drop', function ( de ) {
							de.preventDefault();
							comp.classList.remove( 'hesabix-chat-dragover' );
							if ( ! state.session ) {
								return;
							}
							var dt2 = de.dataTransfer;
							if ( ! dt2 || ! dt2.files || ! dt2.files.length ) {
								return;
							}
							var df = dt2.files[0];
							if ( ! df ) {
								return;
							}
							showFormError( errC, '' );
							postFile( state.session.conversation_id, state.session.visitor_token, df, '' ).then( function () {
								return refreshMessages();
							} ).catch( function ( e ) {
								showFormError( errC, e.message || cfg.strings.errorGeneric );
							} );
						} );
					}
				}
			} )
			.catch( function () {} );
		};
		if ( typeof window.requestIdleCallback === 'function' ) {
			window.requestIdleCallback( runFetch, { timeout: 4000 } );
		} else {
			setTimeout( runFetch, 1 );
		}
	}
	setupVisitorFileUpload();

	chatLogV( 'DOM آماده', {
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

	function ensureWsConnDot() {
		var dot = wsConnLabel.querySelector( '.hesabix-chat-ws-dot' );
		if ( ! dot ) {
			dot = document.createElement( 'span' );
			dot.className = 'hesabix-chat-ws-dot';
			dot.setAttribute( 'aria-hidden', 'true' );
			wsConnLabel.appendChild( dot );
		}
		return dot;
	}

	function updateWsConn( code ) {
		var s = ( cfg.strings && cfg.strings ) || {};
		var isRtl = ( ( cfg.dir || 'rtl' ) + '' ) === 'rtl';
		if ( ! wsConnLabel ) {
			return;
		}
		wsConnLabel.textContent = '';
		ensureWsConnDot();
		if ( code === 'connecting' ) {
			wsConnLabel.className = 'hesabix-chat-ws-conn hesabix-chat-ws-conn--connecting';
			var tCon = s.wsConnecting || ( isRtl ? 'در حال اتصال…' : 'Connecting…' );
			wsConnLabel.title = tCon;
			wsConnLabel.setAttribute( 'aria-label', tCon );
		} else if ( code === 'live' ) {
			wsConnLabel.className = 'hesabix-chat-ws-conn hesabix-chat-ws-conn--live';
			var tLive = s.wsLiveHint || s.wsLive || ( isRtl ? 'اتصال لحظه‌ای برقرار است' : 'Real-time link active' );
			wsConnLabel.title = tLive;
			wsConnLabel.setAttribute( 'aria-label', tLive );
		} else {
			wsConnLabel.className = 'hesabix-chat-ws-conn hesabix-chat-ws-conn--offline';
			var tOff = s.wsOfflineHint || s.wsOffline || ( isRtl ? 'به‌روزرسانی ممکن است با تأخیر باشد' : 'Polling; messages still work' );
			wsConnLabel.title = tOff;
			wsConnLabel.setAttribute( 'aria-label', tOff );
		}
	}

	function updatePeerTypingUI() {
		var s2 = ( cfg.strings && cfg.strings ) || {};
		var isRtl2 = ( ( cfg.dir || 'rtl' ) + '' ) === 'rtl';
		var fallback = s2.agentTyping || ( isRtl2 ? 'پشتیبان در حال تایپ…' : 'Support is typing…' );
		var name = ( state.agentTypingName || '' ).trim();
		var tpl = s2.agentTypingNamed;
		var t = fallback;
		if ( name && tpl ) {
			t = tpl.replace( /\%s/g, name );
		} else if ( name ) {
			t = name + ( isRtl2 ? ' در حال تایپ است…' : ' is typing…' );
		}
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
			if ( msg.type === 'crm_chat.event' && msg.event === 'message.updated' ) {
				refreshMessages().catch( function () {} );
				return;
			}
			if ( msg.type === 'crm_chat.event' && msg.event === 'message.deleted' ) {
				refreshMessages().catch( function () {} );
				return;
			}
			if ( msg.type === 'crm_chat.event' && msg.event === 'conversation.deleted' ) {
				if ( state.session && +msg.conversation_id === +convId ) {
					clearSession();
					state.session = null;
					enterFormMode();
				}
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
					state.agentTypingName = msg.active
						? ( ( msg.actor_name && String( msg.actor_name ) ) || '' ).trim()
						: '';
					updatePeerTypingUI();
					if ( state.agentTyping ) {
						state.agentTypingTimer = setTimeout( function () {
							state.agentTypingTimer = null;
							state.agentTyping = false;
							state.agentTypingName = '';
							updatePeerTypingUI();
						}, 4000 );
					}
				}
				return;
			}
			if ( msg.type === 'crm_chat.event' && msg.event === 'agent.joined' ) {
				if ( +msg.conversation_id === +convId && msg.agent ) {
					var ag = msg.agent;
					var aid = ag.id != null ? String( ag.id ) : '';
					var aname = ( ag.name && String( ag.name ).trim() ) || '';
					var tplJ = ( cfg.strings && cfg.strings.agentJoinedNotice ) || '';
					if ( aname && aid && ! state.seenAgentJoinIds[ aid ] ) {
						state.seenAgentJoinIds[ aid ] = 1;
						state.agentJoinBannerText = tplJ ? tplJ.replace( /\%s/g, aname ) : aname + ' وارد گفتگو شد';
						renderMessages();
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
		if ( state.agentJoinBannerText ) {
			var noticeEl = document.createElement( 'div' );
			noticeEl.className = 'hesabix-chat-chat-notice';
			noticeEl.setAttribute( 'role', 'status' );
			noticeEl.textContent = state.agentJoinBannerText;
			msgBox.appendChild( noticeEl );
		}

		function appendCannedAnswerBubble( cannedBody ) {
			var divS = document.createElement( 'div' );
			divS.className = 'hesabix-chat-bubble hesabix-chat-bubble--agent hesabix-chat-bubble--canned';
			var strongS = document.createElement( 'strong' );
			strongS.textContent = cfg.strings.support;
			var bodyS = document.createElement( 'div' );
			bodyS.className = 'hesabix-chat-bubble-body';
			bodyS.textContent = ( cannedBody || '' ).toString();
			bodyS.style.whiteSpace = 'pre-wrap';
			var metaS = document.createElement( 'div' );
			metaS.className = 'hesabix-chat-bubble-meta hesabix-chat-bubble-meta--agent';
			var cannedLbl = document.createElement( 'span' );
			cannedLbl.className = 'hesabix-chat-canned-badge';
			cannedLbl.textContent = sUi.cannedAnswerLabel || '';
			metaS.appendChild( cannedLbl );
			divS.appendChild( strongS );
			divS.appendChild( bodyS );
			divS.appendChild( metaS );
			msgBox.appendChild( divS );
		}

		state.messages.forEach( function ( m ) {
			var role = ( m.sender_role || '' ).toString();
			var div = document.createElement( 'div' );
			div.className = 'hesabix-chat-bubble hesabix-chat-bubble--' + ( role === 'visitor' ? 'visitor' : 'agent' );
			var sn = ( m.sender_name && String( m.sender_name ).trim() ) || '';
			var label = role === 'visitor' ? cfg.strings.you : ( sn || cfg.strings.support );
			var strong = document.createElement( 'strong' );
			strong.textContent = label;
			var bodyP = document.createElement( 'div' );
			bodyP.textContent = ( m.body || '' ).toString();
			if ( m.file && m.file.original_name && m.file.id ) {
				var fm = ( m.file.mime_type || '' ).toString().toLowerCase();
				var fileDiv = document.createElement( 'div' );
				fileDiv.className = 'hesabix-chat-file';
				var sid = state.session ? state.session.conversation_id : null;
				var stok = state.session ? state.session.visitor_token : null;
				if ( fm.indexOf( 'image/' ) === 0 && sid && stok ) {
					var thumb = document.createElement( 'div' );
					thumb.className = 'hesabix-chat-thumb';
					var vu = visitorFileDownloadUrl( sid, m.file.id );
					fetch( vu, {
						method: 'GET',
						headers: visitorTokenHeaders( stok ),
					} )
						.then( function ( r ) {
							return r.blob();
						} )
						.then( function ( b ) {
							var url = URL.createObjectURL( b );
							var im = document.createElement( 'img' );
							im.className = 'hesabix-chat-thumb-img';
							im.alt = m.file.original_name;
							im.src = url;
							im.onload = function () {
								try {
									URL.revokeObjectURL( url );
								} catch ( eR ) {}
							};
							im.addEventListener( 'click', function () {
								downloadVisitorFile( sid, stok, m.file.id, m.file.original_name ).catch( function () {} );
							} );
							thumb.appendChild( im );
						} )
						.catch( function () {} );
					fileDiv.appendChild( thumb );
				} else if ( fm.indexOf( 'audio/' ) === 0 && sid && stok ) {
					var ap = visitorFileDownloadUrl( sid, m.file.id );
					fetch( ap, { method: 'GET', headers: visitorTokenHeaders( stok ) } )
						.then( function ( r ) {
							return r.blob();
						} )
						.then( function ( blob ) {
							var urlA = URL.createObjectURL( blob );
							var aud = document.createElement( 'audio' );
							aud.controls = true;
							aud.preload = 'metadata';
							aud.src = urlA;
							fileDiv.appendChild( aud );
						} )
						.catch( function () {} );
				} else {
					var dlBtn0 = document.createElement( 'button' );
					dlBtn0.type = 'button';
					dlBtn0.className = 'hesabix-chat-file-dl';
					dlBtn0.textContent = m.file.original_name;
					dlBtn0.addEventListener( 'click', function () {
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
					fileDiv.appendChild( dlBtn0 );
				}
				if ( fm.indexOf( 'image/' ) === 0 || fm.indexOf( 'audio/' ) === 0 ) {
					var dlLink = document.createElement( 'button' );
					dlLink.type = 'button';
					dlLink.className = 'hesabix-chat-file-dl hesabix-chat-file-dl--sub';
					dlLink.textContent = m.file.original_name;
					dlLink.addEventListener( 'click', function () {
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
					fileDiv.appendChild( dlLink );
				}
				bodyP.appendChild( fileDiv );
			}
			var small = document.createElement( 'small' );
			small.className = 'hesabix-chat-msg-time';
			small.textContent = formatTime( m.created_at );
			var meta = document.createElement( 'div' );
			meta.className =
				'hesabix-chat-bubble-meta' +
				( role === 'visitor' ? ' hesabix-chat-bubble-meta--visitor' : ' hesabix-chat-bubble-meta--agent' );
			if ( m.edited_at ) {
				var edSpan = document.createElement( 'span' );
				edSpan.className = 'hesabix-chat-msg-edited';
				edSpan.textContent = ( sUi.msgEdited || ( isRtl3 ? 'ویرایش‌شده' : 'edited' ) ) + ' · ';
				meta.appendChild( edSpan );
			}
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

			var mid = m.id != null ? +m.id : null;
			if ( mid != null ) {
				for ( var ci = 0; ci < state.localCannedAfterVisitor.length; ci++ ) {
					var ce = state.localCannedAfterVisitor[ ci ];
					if ( ce && +ce.afterVisitorMessageId === mid && ce.body ) {
						appendCannedAnswerBubble( ce.body );
					}
				}
			}
		} );

		var qrList = cfg.quickReplies;
		if ( qrList && qrList.length && surface.classList.contains( 'hesabix-chat--step-chat' ) ) {
			var qrRow = document.createElement( 'div' );
			qrRow.className = 'hesabix-chat-quick-replies-row';
			qrList.forEach( function ( item ) {
				if ( ! item || ! item.q ) {
					return;
				}
				var chip = document.createElement( 'button' );
				chip.type = 'button';
				chip.className = 'hesabix-chat-quick-chip';
				chip.textContent = item.q;
				chip.addEventListener( 'click', function () {
					pickQuickReply( item.q, item.a || '' );
				} );
				qrRow.appendChild( chip );
			} );
			if ( qrRow.firstChild ) {
				var qrWrap = document.createElement( 'div' );
				qrWrap.className = 'hesabix-chat-quick-replies';
				var qrTitle = document.createElement( 'div' );
				qrTitle.className = 'hesabix-chat-quick-replies-title';
				qrTitle.textContent = sUi.quickRepliesTitle || '';
				qrWrap.appendChild( qrTitle );
				qrWrap.appendChild( qrRow );
				msgBox.appendChild( qrWrap );
			}
		}
		msgBox.scrollTop = msgBox.scrollHeight;
	}

	function pickQuickReply( questionText, answerText ) {
		if ( ! state.session ) {
			return;
		}
		showFormError( errC, '' );
		postMessage( state.session.conversation_id, state.session.visitor_token, questionText )
			.then( function ( msgData ) {
				var vid = msgData && msgData.id != null ? +msgData.id : null;
				var ans = ( answerText || '' ).toString().trim();
				return refreshMessages().then( function () {
					if ( vid != null && ans ) {
						state.localCannedAfterVisitor.push( { afterVisitorMessageId: vid, body: ans } );
					}
					renderMessages();
				} );
			} )
			.catch( function ( e ) {
				showFormError( errC, e.message || cfg.strings.errorGeneric );
			} );
	}

	function refreshMessages() {
		if ( ! state.session ) {
			return;
		}
		return listMessages( state.session.conversation_id, state.session.visitor_token, 100 ).then( function ( items ) {
			maybePlayAgentReplySound( items );
			state.messages = items;
			var have = {};
			( items || [] ).forEach( function ( x ) {
				if ( x && x.id != null ) {
					have[ +x.id ] = 1;
				}
			} );
			state.localCannedAfterVisitor = ( state.localCannedAfterVisitor || [] ).filter( function ( e ) {
				return e && e.afterVisitorMessageId != null && have[ +e.afterVisitorMessageId ];
			} );
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
		teardownVisitorPageUrlTracking();
		state.messages = [];
		state.localCannedAfterVisitor = [];
		state.agentSoundPrimed = false;
		state.lastAgentMsgNotifiedId = 0;
		state.seenAgentJoinIds = {};
		state.agentJoinBannerText = '';
		state.agentTypingName = '';
		msgBox.innerHTML = '';
		formEl.classList.remove( 'hesabix-chat--hidden' );
		comp.classList.add( 'hesabix-chat--hidden' );
		surface.classList.remove( 'hesabix-chat--step-chat' );
		surface.classList.add( 'hesabix-chat--step-form' );
		if ( wsConnLabel ) {
			wsConnLabel.innerHTML = '';
			wsConnLabel.className = 'hesabix-chat-ws-conn';
			wsConnLabel.title = '';
			wsConnLabel.removeAttribute( 'aria-label' );
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
		state.agentTypingName = '';
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
		installVisitorPageUrlTracking();
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
		afterSessionReady( true )
			.then( function () {
				deferUntilPagePaint( function () {
					runLauncherBoot( true );
				} );
			} )
			.catch( function ( se ) {
				chatLogV( 'بازیابی نشست محلی ناموفق', se );
				clearSession();
				state.session = null;
				enterFormMode();
				deferUntilPagePaint( function () {
					runLauncherBoot( false );
				} );
			} );
	} else {
		deferUntilPagePaint( function () {
			runLauncherBoot( false );
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
				state.seenAgentJoinIds = {};
				state.agentJoinBannerText = '';
				state.agentTypingName = '';
				saveSession( cid, tok );
				state.session = { conversation_id: cid, visitor_token: tok };
				return afterSessionReady( false );
			} )
			.catch( function ( e ) {
				chatLogV( 'startConversation خطا', e && e.message, e );
				showFormError( errEl, e.message || cfg.strings.errorGeneric );
			} );
	} );

	function submitComposerMessage() {
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
	}
	sendBtn.addEventListener( 'click', submitComposerMessage );
	ta.addEventListener( 'keydown', function ( e ) {
		if ( e.key !== 'Enter' ) {
			return;
		}
		if ( ! ( e.ctrlKey || e.metaKey ) ) {
			return;
		}
		e.preventDefault();
		submitComposerMessage();
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

	function applyLauncherIdleIfNeeded() {
		if ( ! btn ) {
			return;
		}
		btn.classList.remove( 'hesabix-chat-launcher--idle' );
		btn.removeAttribute( 'data-hesabix-idle-anim' );
		var anim = ( cfg.launcherIdleAnimation || 'none' ).toString();
		if ( state.open || anim === 'none' || ! anim ) {
			return;
		}
		btn.classList.add( 'hesabix-chat-launcher--idle' );
		btn.setAttribute( 'data-hesabix-idle-anim', anim );
	}

	function clearLauncherAttentionTimer() {
		if ( launcherAttentionTimer ) {
			clearTimeout( launcherAttentionTimer );
			launcherAttentionTimer = null;
		}
	}

	function scheduleLauncherAttention() {
		clearLauncherAttentionTimer();
		if ( ! btn ) {
			return;
		}
		var anim = ( cfg.launcherIdleAnimation || 'none' ).toString();
		if ( anim === 'none' || ! anim ) {
			return;
		}
		btn.classList.remove( 'hesabix-chat-launcher--idle' );
		btn.removeAttribute( 'data-hesabix-idle-anim' );
		var d = Number( cfg.launcherAttentionDelaySec );
		if ( isNaN( d ) || d < 0 ) {
			d = 0;
		}
		if ( d > 600 ) {
			d = 600;
		}
		launcherAttentionTimer = setTimeout( function () {
			launcherAttentionTimer = null;
			applyLauncherIdleIfNeeded();
		}, d * 1000 );
	}

	function setOpen( v, skipDataRefresh ) {
		state.open = v;
		btn.setAttribute( 'aria-expanded', v ? 'true' : 'false' );
		if ( v ) {
			primeAgentSoundForAutoplay();
			clearLauncherAttentionTimer();
			btn.classList.remove( 'hesabix-chat-launcher--idle' );
			btn.removeAttribute( 'data-hesabix-idle-anim' );
			panel.classList.remove( 'hesabix-chat--hidden' );
			( function () {
				var st = ( typeof getComputedStyle === 'function' ) ? getComputedStyle( panel ) : null;
				var r = ( typeof panel.getBoundingClientRect === 'function' ) ? panel.getBoundingClientRect() : null;
				chatLogV( 'پنل باز', {
					hasSession: Boolean( state.session ),
					className: panel.className,
					rect: r ? { w: r.width, h: r.height, top: r.top, left: r.left } : null,
					css: st ? { zIndex: st.zIndex, display: st.display, visibility: st.visibility, opacity: st.opacity, pointerEvents: st.pointerEvents } : null
				} );
			} )();
			if ( state.session ) {
				if ( skipDataRefresh ) {
					bindRealtime();
				} else {
					refreshMessages()
						.then( function () {
							bindRealtime();
						} )
						.catch( function () {} );
				}
			}
		} else {
			panel.classList.add( 'hesabix-chat--hidden' );
			chatLogV( 'پنل بسته' );
			unbindRealtime();
			applyLauncherIdleIfNeeded();
		}
		persistRememberedPanelOpen( v );
	}

	btn.addEventListener( 'click', function ( ev ) {
		primeAgentSoundForAutoplay();
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

	function deferUntilPagePaint( fn ) {
		var run = function () {
			if ( typeof window.requestAnimationFrame === 'function' ) {
				window.requestAnimationFrame( function () {
					window.requestAnimationFrame( fn );
				} );
			} else {
				setTimeout( fn, 0 );
			}
		};
		if ( document.readyState === 'complete' ) {
			run();
		} else {
			window.addEventListener( 'load', run, { once: true } );
		}
	}

	function wantsOpenOnLoad() {
		var opl = cfg.openPanelOnLoad;
		return opl === true || opl === 1 || opl === '1';
	}

	function openPanelDelayMs() {
		var odl = Number( cfg.openPanelDelaySec );
		if ( isNaN( odl ) || odl < 0 ) {
			odl = 0;
		}
		if ( odl > 120 ) {
			odl = 120;
		}
		return odl * 1000;
	}

	function runLauncherBoot( skipRefreshOnOpen ) {
		scheduleLauncherAttention();
		var remembered = readRememberedPanelOpen();
		if ( remembered === false ) {
			return;
		}
		if ( remembered === true ) {
			setTimeout( function () {
				setOpen( true, skipRefreshOnOpen === true );
			}, 0 );
			return;
		}
		if ( ! wantsOpenOnLoad() ) {
			return;
		}
		var ms = openPanelDelayMs();
		setTimeout( function () {
			setOpen( true, skipRefreshOnOpen === true );
		}, ms );
	}
} )();
