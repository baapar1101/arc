<?php
/**
 * ابزارک کلاسیک «کاتالوگ شبکه تأمین».
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * ثبت و رندر ابزارک.
 */
final class Shabake_Tamin_Widget_Controller {

	/**
	 * @var self|null
	 */
	private static $instance = null;

	/**
	 * @return self
	 */
	public static function instance() {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	private function __construct() {
		add_action( 'widgets_init', array( $this, 'register' ) );
	}

	/**
	 * ثبت ابزارک.
	 */
	public function register() {
		register_widget( 'Shabake_Tamin_Catalog_Widget' );
	}
}

/**
 * ابزارک سایدبار.
 */
class Shabake_Tamin_Catalog_Widget extends WP_Widget {

	/**
	 * سازنده.
	 */
	public function __construct() {
		parent::__construct(
			'shabake_tamin_catalog',
			__( 'کاتالوگ شبکه تأمین', 'shabake-tamin' ),
			array(
				'description'                 => __( 'نمایش کاتالوگ عمومی Hesabix (همهٔ تأمین‌کنندگان یا فیلترشده).', 'shabake-tamin' ),
				'classname'                   => 'shabake-tamin-catalog-widget',
				'customize_selective_refresh' => true,
			)
		);
	}

	/**
	 * @param array<string, string> $args     آرگومان‌های تم.
	 * @param array<string, mixed>  $instance ذخیرهٔ ابزارک.
	 */
	public function widget( $args, $instance ) {
		$instance = wp_parse_args(
			(array) $instance,
			array(
				'title'             => '',
				'business_id'       => '',
				'category_id'       => '',
				'province'          => '',
				'city'              => '',
				'location_filters'    => '0',
				'province_suggest'    => '1',
				'show_details'        => '1',
				'columns'             => '4',
				'search'              => '1',
				'take'                => '20',
			)
		);

		$title = apply_filters( 'widget_title', $instance['title'], $instance, $this->id_base );

		$html = $args['before_widget'];
		if ( is_string( $title ) && '' !== trim( $title ) ) {
			$html .= $args['before_title'] . esc_html( $title ) . $args['after_title'];
		}

		$bid_raw = trim( (string) $instance['business_id'] );
		if ( '' === $bid_raw ) {
			$business_id = Shabake_Tamin_Catalog::resolve_business_id( '' );
		} else {
			$id          = absint( $bid_raw );
			$business_id = $id > 0 ? $id : null;
		}

		$cid_raw = trim( (string) $instance['category_id'] );
		$category_id = '' === $cid_raw ? null : absint( $cid_raw );
		if ( $category_id <= 0 ) {
			$category_id = null;
		}

		$config = array(
			'businessId'            => $business_id,
			'categoryId'            => $category_id,
			'province'              => (string) $instance['province'],
			'city'                  => (string) $instance['city'],
			'locationFilters'       => in_array( (string) $instance['location_filters'], array( '1', 'true', 'yes' ), true ),
			'provinceSuggestions'   => ! in_array( (string) $instance['province_suggest'], array( '0', 'false', 'no' ), true ),
			'showProductDetails'    => ! in_array( (string) $instance['show_details'], array( '0', 'false', 'no' ), true ),
			'columns'               => (int) $instance['columns'],
			'search'                => in_array( (string) $instance['search'], array( '1', 'true', 'yes' ), true ),
			'take'                  => (int) $instance['take'],
		);

		$config = apply_filters( 'shabake_tamin_widget_catalog_config', $config, $instance );

		$html .= Shabake_Tamin_Catalog::render_html( $config, 'widget', $instance );
		$html .= $args['after_widget'];

		// phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped
		echo $html;
	}

	/**
	 * فرم تنظیمات ابزارک.
	 *
	 * @param array<string, mixed> $instance نمونه.
	 */
	public function form( $instance ) {
		$instance = wp_parse_args(
			(array) $instance,
			array(
				'title'             => '',
				'business_id'       => '',
				'category_id'       => '',
				'province'          => '',
				'city'              => '',
				'location_filters'    => '0',
				'province_suggest'    => '1',
				'show_details'        => '1',
				'columns'             => '4',
				'search'              => '1',
				'take'                => '20',
			)
		);
		$fid = $this->get_field_id( 'title' );
		?>
		<p>
			<label for="<?php echo esc_attr( $fid ); ?>"><?php esc_html_e( 'عنوان (اختیاری)', 'shabake-tamin' ); ?></label>
			<input class="widefat" id="<?php echo esc_attr( $fid ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'title' ) ); ?>"
				type="text" value="<?php echo esc_attr( (string) $instance['title'] ); ?>" />
		</p>
		<p>
			<label for="<?php echo esc_attr( $this->get_field_id( 'business_id' ) ); ?>"><?php esc_html_e( 'شناسهٔ کسب‌وکار (خالی = همه یا پیش‌فرض تنظیمات)', 'shabake-tamin' ); ?></label>
			<input class="widefat" id="<?php echo esc_attr( $this->get_field_id( 'business_id' ) ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'business_id' ) ); ?>"
				type="text" value="<?php echo esc_attr( (string) $instance['business_id'] ); ?>" />
		</p>
		<p>
			<label for="<?php echo esc_attr( $this->get_field_id( 'category_id' ) ); ?>"><?php esc_html_e( 'شناسهٔ دسته', 'shabake-tamin' ); ?></label>
			<input class="widefat" id="<?php echo esc_attr( $this->get_field_id( 'category_id' ) ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'category_id' ) ); ?>"
				type="text" value="<?php echo esc_attr( (string) $instance['category_id'] ); ?>" />
		</p>
		<p>
			<label for="<?php echo esc_attr( $this->get_field_id( 'province' ) ); ?>"><?php esc_html_e( 'استان (پیش‌فرض متن)', 'shabake-tamin' ); ?></label>
			<input class="widefat" id="<?php echo esc_attr( $this->get_field_id( 'province' ) ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'province' ) ); ?>"
				type="text" value="<?php echo esc_attr( (string) $instance['province'] ); ?>" />
		</p>
		<p>
			<label for="<?php echo esc_attr( $this->get_field_id( 'city' ) ); ?>"><?php esc_html_e( 'شهر (پیش‌فرض متن)', 'shabake-tamin' ); ?></label>
			<input class="widefat" id="<?php echo esc_attr( $this->get_field_id( 'city' ) ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'city' ) ); ?>"
				type="text" value="<?php echo esc_attr( (string) $instance['city'] ); ?>" />
		</p>
		<p>
			<input id="<?php echo esc_attr( $this->get_field_id( 'location_filters' ) ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'location_filters' ) ); ?>"
				type="checkbox" value="1" <?php checked( '1', (string) $instance['location_filters'] ); ?> />
			<label for="<?php echo esc_attr( $this->get_field_id( 'location_filters' ) ); ?>"><?php esc_html_e( 'نمایش فیلدهای استان/شهر برای بازدیدکننده', 'shabake-tamin' ); ?></label>
		</p>
		<p>
			<input id="<?php echo esc_attr( $this->get_field_id( 'province_suggest' ) ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'province_suggest' ) ); ?>"
				type="checkbox" value="1" <?php checked( '1', (string) $instance['province_suggest'] ); ?> />
			<label for="<?php echo esc_attr( $this->get_field_id( 'province_suggest' ) ); ?>"><?php esc_html_e( 'پیشنهاد نام استان (datalist)', 'shabake-tamin' ); ?></label>
		</p>
		<p>
			<input id="<?php echo esc_attr( $this->get_field_id( 'show_details' ) ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'show_details' ) ); ?>"
				type="checkbox" value="1" <?php checked( '1', (string) $instance['show_details'] ); ?> />
			<label for="<?php echo esc_attr( $this->get_field_id( 'show_details' ) ); ?>"><?php esc_html_e( 'دکمهٔ جزئیات کالا', 'shabake-tamin' ); ?></label>
		</p>
		<p>
			<label for="<?php echo esc_attr( $this->get_field_id( 'columns' ) ); ?>"><?php esc_html_e( 'ستون‌ها (۲–۶)', 'shabake-tamin' ); ?></label>
			<input class="tiny-text" id="<?php echo esc_attr( $this->get_field_id( 'columns' ) ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'columns' ) ); ?>"
				type="number" min="2" max="6" step="1" value="<?php echo esc_attr( (string) (int) $instance['columns'] ); ?>" />
		</p>
		<p>
			<label for="<?php echo esc_attr( $this->get_field_id( 'take' ) ); ?>"><?php esc_html_e( 'تعداد در هر بار', 'shabake-tamin' ); ?></label>
			<input class="tiny-text" id="<?php echo esc_attr( $this->get_field_id( 'take' ) ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'take' ) ); ?>"
				type="number" min="1" max="100" step="1" value="<?php echo esc_attr( (string) (int) $instance['take'] ); ?>" />
		</p>
		<p>
			<input id="<?php echo esc_attr( $this->get_field_id( 'search' ) ); ?>" name="<?php echo esc_attr( $this->get_field_name( 'search' ) ); ?>"
				type="checkbox" value="1" <?php checked( '1', (string) $instance['search'] ); ?> />
			<label for="<?php echo esc_attr( $this->get_field_id( 'search' ) ); ?>"><?php esc_html_e( 'نوار جستجو', 'shabake-tamin' ); ?></label>
		</p>
		<?php
	}

	/**
	 * ذخیره.
	 *
	 * @param array<string, mixed> $new_instance ورودی جدید.
	 * @param array<string, mixed> $old_instance قبلی.
	 * @return array<string, mixed>
	 */
	public function update( $new_instance, $old_instance ) {
		unset( $old_instance );
		$out = array();
		$out['title']               = isset( $new_instance['title'] ) ? sanitize_text_field( (string) $new_instance['title'] ) : '';
		$out['business_id']         = isset( $new_instance['business_id'] ) ? sanitize_text_field( (string) $new_instance['business_id'] ) : '';
		$out['category_id']         = isset( $new_instance['category_id'] ) ? sanitize_text_field( (string) $new_instance['category_id'] ) : '';
		$out['province']            = isset( $new_instance['province'] ) ? sanitize_text_field( (string) $new_instance['province'] ) : '';
		$out['city']                = isset( $new_instance['city'] ) ? sanitize_text_field( (string) $new_instance['city'] ) : '';
		$out['location_filters']    = ! empty( $new_instance['location_filters'] ) ? '1' : '0';
		$out['province_suggest']    = ! empty( $new_instance['province_suggest'] ) ? '1' : '0';
		$out['show_details']        = ! empty( $new_instance['show_details'] ) ? '1' : '0';
		$out['columns']             = isset( $new_instance['columns'] ) ? max( 2, min( 6, (int) $new_instance['columns'] ) ) : 4;
		$out['take']                = isset( $new_instance['take'] ) ? max( 1, min( 100, (int) $new_instance['take'] ) ) : 20;
		$out['search']              = ! empty( $new_instance['search'] ) ? '1' : '0';
		return $out;
	}
}
