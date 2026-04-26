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
	} );
} )( jQuery );
