<?php
/**
 * WooCommerce buy-now and entitlement.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hhelp_WooCommerce
 */
class Hhelp_WooCommerce {

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

	/**
	 * Constructor.
	 */
	private function __construct() {
		add_action( 'woocommerce_order_status_completed', array( $this, 'grant_order' ) );
		add_action( 'woocommerce_order_status_processing', array( $this, 'grant_order' ) );
		add_action( 'wp_ajax_hhelp_buy_now', array( $this, 'ajax_buy_now' ) );
		add_action( 'wp_ajax_nopriv_hhelp_buy_now', array( $this, 'ajax_buy_now' ) );
		add_action( 'woocommerce_product_options_general_product_data', array( $this, 'product_field' ) );
		add_action( 'woocommerce_process_product_meta', array( $this, 'save_product_field' ) );
		add_action( 'init', array( $this, 'my_account_endpoint' ) );
		add_filter( 'woocommerce_account_menu_items', array( $this, 'account_menu' ) );
		add_action( 'woocommerce_account_help-library_endpoint', array( $this, 'account_content' ) );
		add_filter( 'woocommerce_login_redirect', array( $this, 'maybe_redirect_after_login' ), 20, 2 );
	}

	/**
	 * Grant access for all products in order.
	 *
	 * @param int $order_id Order ID.
	 */
	public function grant_order( $order_id ) {
		$order = wc_get_order( $order_id );
		if ( ! $order ) {
			return;
		}
		$user_id = (int) $order->get_user_id();
		if ( $user_id <= 0 ) {
			$email = $order->get_billing_email();
			if ( $email ) {
				$user = get_user_by( 'email', $email );
				if ( $user ) {
					$user_id = (int) $user->ID;
				}
			}
		}
		if ( $user_id <= 0 ) {
			return;
		}

		foreach ( $order->get_items() as $item ) {
			$product_id = (int) $item->get_product_id();
			if ( $product_id ) {
				Hhelp_Access::grant_from_product( $user_id, $product_id );
			}
		}

		$order->update_meta_data( '_hhelp_access_granted', 1 );
		$order->save();
	}

	/**
	 * AJAX: empty cart, add product, return checkout URL (+ optional return lesson).
	 */
	public function ajax_buy_now() {
		check_ajax_referer( 'hhelp_front', 'nonce' );

		if ( ! function_exists( 'WC' ) ) {
			wp_send_json_error( array( 'message' => __( 'فروشگاه در دسترس نیست.', 'hesabix-help' ) ), 400 );
		}

		$product_id = isset( $_POST['product_id'] ) ? absint( $_POST['product_id'] ) : 0;
		$lesson_id  = isset( $_POST['lesson_id'] ) ? absint( $_POST['lesson_id'] ) : 0;

		if ( $product_id <= 0 ) {
			wp_send_json_error( array( 'message' => __( 'محصول نامعتبر است.', 'hesabix-help' ) ), 400 );
		}

		$product = wc_get_product( $product_id );
		if ( ! $product || ! $product->is_purchasable() ) {
			wp_send_json_error( array( 'message' => __( 'این محصول قابل خرید نیست.', 'hesabix-help' ) ), 400 );
		}

		if ( ! is_user_logged_in() ) {
			$redirect = $lesson_id ? get_permalink( $lesson_id ) : hhelp_hub_url();
			wp_send_json_error(
				array(
					'message'  => __( 'برای خرید وارد شوید.', 'hesabix-help' ),
					'loginUrl' => Hhelp_Access::login_url( $redirect ),
				),
				401
			);
		}

		WC()->cart->empty_cart();
		$added = WC()->cart->add_to_cart( $product_id, 1 );
		if ( ! $added ) {
			wp_send_json_error( array( 'message' => __( 'افزودن به سبد ناموفق بود.', 'hesabix-help' ) ), 400 );
		}

		if ( $lesson_id ) {
			WC()->session->set( 'hhelp_return_lesson', $lesson_id );
		}

		wp_send_json_success(
			array(
				'checkoutUrl' => wc_get_checkout_url(),
			)
		);
	}

	/**
	 * Product admin field for grant IDs.
	 */
	public function product_field() {
		woocommerce_wp_text_input(
			array(
				'id'          => Hhelp_Access::PRODUCT_GRANTS,
				'label'       => __( 'دسترسی راهنما (IDs)', 'hesabix-help' ),
				'description' => __( 'شناسه مطالب راهنما با ویرگول، یا children_of:ID یا all', 'hesabix-help' ),
				'desc_tip'    => true,
			)
		);
	}

	/**
	 * @param int $post_id Product ID.
	 */
	public function save_product_field( $post_id ) {
		// phpcs:ignore WordPress.Security.NonceVerification.Missing
		$value = isset( $_POST[ Hhelp_Access::PRODUCT_GRANTS ] ) ? sanitize_text_field( wp_unslash( $_POST[ Hhelp_Access::PRODUCT_GRANTS ] ) ) : '';
		update_post_meta( $post_id, Hhelp_Access::PRODUCT_GRANTS, $value );
	}

	/**
	 * My Account endpoint.
	 */
	public function my_account_endpoint() {
		add_rewrite_endpoint( 'help-library', EP_ROOT | EP_PAGES );
	}

	/**
	 * @param array<string, string> $items Menu items.
	 * @return array<string, string>
	 */
	public function account_menu( $items ) {
		$new = array();
		foreach ( $items as $key => $label ) {
			$new[ $key ] = $label;
			if ( 'dashboard' === $key ) {
				$new['help-library'] = __( 'آموزش‌های من', 'hesabix-help' );
			}
		}
		if ( ! isset( $new['help-library'] ) ) {
			$new['help-library'] = __( 'آموزش‌های من', 'hesabix-help' );
		}
		return $new;
	}

	/**
	 * My Account content.
	 */
	public function account_content() {
		$user_id = get_current_user_id();
		$all     = (bool) get_user_meta( $user_id, Hhelp_Access::USER_META_ALL, true );
		$ids     = Hhelp_Access::user_access_ids( $user_id );

		echo '<div class="hx-help-account">';
		echo '<h2>' . esc_html__( 'آموزش‌ها و راهنماهای خریداری‌شده', 'hesabix-help' ) . '</h2>';

		if ( $all ) {
			echo '<p>' . esc_html__( 'شما به همهٔ مطالب پولی راهنما دسترسی دارید.', 'hesabix-help' ) . '</p>';
			echo '<p><a class="button" href="' . esc_url( hhelp_hub_url() ) . '">' . esc_html__( 'ورود به راهنمای جامع', 'hesabix-help' ) . '</a></p>';
			echo '</div>';
			return;
		}

		if ( empty( $ids ) ) {
			echo '<p>' . esc_html__( 'هنوز آموزش پولی خریداری نکرده‌اید.', 'hesabix-help' ) . '</p>';
			echo '<p><a class="button" href="' . esc_url( hhelp_hub_url() ) . '">' . esc_html__( 'مشاهده راهنمای جامع', 'hesabix-help' ) . '</a></p>';
			echo '</div>';
			return;
		}

		$posts = get_posts(
			array(
				'post_type'      => HHELP_CPT,
				'post__in'       => $ids,
				'posts_per_page' => -1,
				'orderby'        => hhelp_query_order(),
			)
		);

		echo '<ul class="hx-help-account__list">';
		foreach ( $posts as $p ) {
			printf(
				'<li><a href="%s">%s</a></li>',
				esc_url( get_permalink( $p ) ),
				esc_html( get_the_title( $p ) )
			);
		}
		echo '</ul></div>';
	}

	/**
	 * After checkout, Woo may redirect; also support return lesson via session on thankyou.
	 *
	 * @param string  $redirect Redirect.
	 * @param WP_User $user     User.
	 * @return string
	 */
	public function maybe_redirect_after_login( $redirect, $user ) {
		return $redirect;
	}

	/**
	 * Checkout thank-you redirect to lesson.
	 */
	public static function thankyou_redirect_url( $order_id ) {
		if ( ! function_exists( 'WC' ) || ! WC()->session ) {
			return '';
		}
		$lesson_id = (int) WC()->session->get( 'hhelp_return_lesson' );
		if ( $lesson_id > 0 ) {
			WC()->session->set( 'hhelp_return_lesson', null );
			$link = get_permalink( $lesson_id );
			return $link ? $link : '';
		}
		return '';
	}
}

add_action(
	'woocommerce_thankyou',
	static function ( $order_id ) {
		$url = Hhelp_WooCommerce::thankyou_redirect_url( $order_id );
		if ( $url && ! headers_sent() ) {
			wp_safe_redirect( $url );
			exit;
		}
	},
	5
);
