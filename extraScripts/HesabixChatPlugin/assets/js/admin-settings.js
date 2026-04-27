( function ( $ ) {
	'use strict';
	$( function () {
		$( '.hesabix-color-field' ).wpColorPicker();

		var frame;
		$( document ).on( 'click', '#hesabix_logo_select', function ( e ) {
			e.preventDefault();
			if ( frame ) {
				frame.open();
				return;
			}
			frame = wp.media( {
				title: $( this ).data( 'title' ) || 'Hesabix',
				library: { type: 'image' },
				multiple: false,
			} );
			frame.on( 'select', function () {
				var a = frame.state().get( 'selection' ).first().toJSON();
				var u = a.url;
				$( '#hesabix_header_logo' ).val( u );
				$( '#hesabix_logo_preview' ).attr( 'src', u );
				$( '#hesabix_logo_preview_wrap' ).show();
			} );
			frame.open();
		} );
		$( document ).on( 'click', '#hesabix_logo_clear', function ( e ) {
			e.preventDefault();
			$( '#hesabix_header_logo' ).val( '' );
			$( '#hesabix_logo_preview' ).attr( 'src', '' );
			$( '#hesabix_logo_preview_wrap' ).hide();
		} );

		var $tabWrap = $( '.hesabix-chat-settings-tabs' );
		if ( $tabWrap.length ) {
			var $tabs = $tabWrap.find( '.nav-tab' );
			var $panels = $( '.hesabix-chat-tab-panel' );
			function activateTab( id ) {
				$tabs.removeClass( 'nav-tab-active' ).attr( 'aria-selected', 'false' );
				$tabs.filter( '[data-tab="' + id + '"]' ).addClass( 'nav-tab-active' ).attr( 'aria-selected', 'true' );
				$panels.attr( 'hidden', true );
				$panels.filter( '[data-tab="' + id + '"]' ).removeAttr( 'hidden' );
				if ( window.history && window.history.replaceState ) {
					window.history.replaceState( null, '', '#hesabix-tab-' + id );
				}
			}
			$tabWrap.on( 'click', '.nav-tab', function ( e ) {
				e.preventDefault();
				var id = $( this ).data( 'tab' );
				if ( id ) {
					activateTab( id );
				}
			} );
			var m = /^#hesabix-tab-(.+)$/.exec( window.location.hash || '' );
			if ( m && m[1] && $panels.filter( '[data-tab="' + m[1] + '"]' ).length ) {
				activateTab( m[1] );
			}
		}
	} );
} )( jQuery );
