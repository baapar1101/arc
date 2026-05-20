/**
 * بلوک گوتنبرگ — فقط وابستگی به اسکریپت‌های هستهٔ وردپرس (wp-*).
 */
( function ( blocks, element, blockEditor, components, i18n ) {
	'use strict';

	var el = element.createElement;
	var Fragment = element.Fragment;
	var __ = i18n.__;
	var InspectorControls = blockEditor.InspectorControls;
	var PanelBody = components.PanelBody;
	var TextControl = components.TextControl;
	var ToggleControl = components.ToggleControl;
	var RangeControl = components.RangeControl;

	blocks.registerBlockType( 'shabake-tamin/catalog', {
		edit: function ( props ) {
			var a = props.attributes;
			var set = props.setAttributes;

			return el(
				Fragment,
				null,
				el(
					InspectorControls,
					null,
					el(
						PanelBody,
						{ title: __( 'فیلتر کاتالوگ', 'shabake-tamin' ), initialOpen: true },
						el( TextControl, {
							label: __( 'شناسهٔ کسب‌وکار (خالی = همه یا پیش‌فرض تنظیمات)', 'shabake-tamin' ),
							value: a.businessId,
							onChange: function ( v ) {
								set( { businessId: v == null ? '' : String( v ) } );
							},
							type: 'text',
							help: __(
								'اگر خالی بماند و در تنظیمات افزونه هم «پیش‌فرض» نباشد، بازدیدکننده همهٔ کسب‌وکارها را می‌بیند.',
								'shabake-tamin'
							),
						} ),
						el( TextControl, {
							label: __( 'شناسهٔ دسته (اختیاری)', 'shabake-tamin' ),
							value: a.categoryId ? String( a.categoryId ) : '',
							onChange: function ( v ) {
								var n = parseInt( v, 10 );
								set( { categoryId: isNaN( n ) || n <= 0 ? 0 : n } );
							},
						} ),
						el( TextControl, {
							label: __( 'استان (فیلتر متن)', 'shabake-tamin' ),
							value: a.province,
							onChange: function ( v ) {
								set( { province: v == null ? '' : String( v ) } );
							},
						} ),
						el( TextControl, {
							label: __( 'شهر (فیلتر متن)', 'shabake-tamin' ),
							value: a.city,
							onChange: function ( v ) {
								set( { city: v == null ? '' : String( v ) } );
							},
						} ),
						el( ToggleControl, {
							label: __( 'فیلدهای استان/شهر برای بازدیدکننده', 'shabake-tamin' ),
							checked: !! a.locationFilters,
							onChange: function ( v ) {
								set( { locationFilters: !! v } );
							},
							help: __(
								'اگر روشن باشد، بازدیدکننده می‌تواند استان و شهر را عوض کند و با «اعمال فیلتر مکان» لیست را به‌روز کند.',
								'shabake-tamin'
							),
						} ),
						el( ToggleControl, {
							label: __( 'پیشنهاد استان (datalist)', 'shabake-tamin' ),
							checked: !! a.provinceSuggestions,
							disabled: ! a.locationFilters,
							onChange: function ( v ) {
								set( { provinceSuggestions: !! v } );
							},
							help: ! a.locationFilters
								? __( 'ابتدا «فیلدهای استان/شهر» را روشن کنید.', 'shabake-tamin' )
								: __( 'لیست ثابت ۳۱ استان ایران در فیلد استان.', 'shabake-tamin' ),
						} )
					),
					el(
						PanelBody,
						{ title: __( 'نمایش', 'shabake-tamin' ) },
						el( RangeControl, {
							label: __( 'تعداد ستون', 'shabake-tamin' ),
							value: a.columns,
							onChange: function ( v ) {
								set( { columns: v } );
							},
							min: 2,
							max: 6,
							step: 1,
						} ),
						el( RangeControl, {
							label: __( 'تعداد در هر بار', 'shabake-tamin' ),
							value: a.take,
							onChange: function ( v ) {
								set( { take: v } );
							},
							min: 1,
							max: 100,
							step: 1,
						} ),
						el( ToggleControl, {
							label: __( 'نوار جستجو', 'shabake-tamin' ),
							checked: !! a.search,
							onChange: function ( v ) {
								set( { search: !! v } );
							},
						} ),
						el( ToggleControl, {
							label: __( 'دکمهٔ جزئیات کالا', 'shabake-tamin' ),
							checked: !! a.showProductDetails,
							onChange: function ( v ) {
								set( { showProductDetails: !! v } );
							},
							help: __( 'باز کردن مودال با توضیحات و تماس.', 'shabake-tamin' ),
						} ),
						el( ToggleControl, {
							label: __( 'چیدمان صفحهٔ کامل (هیرو + شمارنده)', 'shabake-tamin' ),
							checked: !! a.pageLayout,
							onChange: function ( v ) {
								set( { pageLayout: !! v } );
							},
							help: __(
								'برای برگهٔ اختصاصی یا شورت‌کد با page=1؛ استایل تمام‌عرض و نوار خلاصهٔ نتایج.',
								'shabake-tamin'
							),
						} )
					)
				),
				el(
					'div',
					{
						className: 'st-block-placeholder',
						style: {
							direction: 'rtl',
							textAlign: 'right',
							padding: '1rem',
							border: '1px dashed #ccc',
							borderRadius: '4px',
							background: '#fafafa',
						},
					},
					el( 'strong', null, __( 'کاتالوگ شبکه تأمین', 'shabake-tamin' ) ),
					el(
						'p',
						{ style: { margin: '0.5rem 0 0', fontSize: '13px', color: '#555' } },
						__( 'پیش‌نمایش در سایت و صفحهٔ اصلی دیده می‌شود.', 'shabake-tamin' )
					)
				)
			);
		},
		save: function () {
			return null;
		},
	} );
} )( window.wp.blocks, window.wp.element, window.wp.blockEditor, window.wp.components, window.wp.i18n );
