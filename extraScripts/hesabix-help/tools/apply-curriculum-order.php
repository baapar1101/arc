<?php
/**
 * One-shot: set help syllabus menu_order + featured starter path.
 *
 * Usage: wp eval-file tools/apply-curriculum-order.php --allow-root
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

$orders = array(
	// 1. شروع و راه‌اندازی
	759 => 10,
	761 => 10,
	763 => 20,
	765 => 30,
	767 => 40,
	769 => 50,
	// 2. اشخاص
	771 => 20,
	773 => 10,
	775 => 20,
	777 => 30,
	// 3. کالا و خدمات
	779 => 30,
	781 => 10,
	783 => 20,
	785 => 30,
	787 => 40,
	// 4. انبار و موجودی
	809 => 40,
	811 => 10,
	813 => 20,
	815 => 30,
	// 5. فروش و فاکتور
	789 => 50,
	791 => 10,
	793 => 20,
	795 => 30,
	797 => 40,
	799 => 50,
	// 6. بانکداری و نقدینگی
	801 => 60,
	803 => 10,
	805 => 20,
	807 => 30,
	// 7. حسابداری و اسناد
	817 => 70,
	819 => 10,
	821 => 20,
	823 => 30,
	825 => 40,
	// 8. گزارش‌ها
	827 => 80,
	829 => 10,
	831 => 20,
	// 9. مالیات و سامانه مودیان
	833 => 90,
	835 => 10,
	837 => 20,
	// 10. CRM
	839 => 100,
	841 => 10,
	843 => 20,
	// 11. هوش مصنوعی
	845 => 110,
	847 => 10,
	// 12. اتوماسیون و ورک‌فلو
	849 => 120,
	851 => 10,
	// 13. افزونه‌ها و یکپارچه‌سازی
	853 => 130,
	855 => 10,
	857 => 20,
	// 14. افزونه‌های تخصصی
	865 => 140,
	867 => 10,
	869 => 20,
	871 => 30,
	873 => 40,
	875 => 50,
	877 => 60,
	// 15. پرسش‌های متداول
	859 => 150,
	861 => 10,
	863 => 20,
);

$featured_on = array( 761, 763, 765, 773, 781, 791 );

$ok     = 0;
$miss   = 0;
foreach ( $orders as $id => $order ) {
	$post = get_post( $id );
	if ( ! $post || HHELP_CPT !== $post->post_type ) {
		echo "MISSING {$id}\n";
		++$miss;
		continue;
	}
	wp_update_post(
		array(
			'ID'         => $id,
			'menu_order' => $order,
		)
	);
	++$ok;
}

$ids = get_posts(
	array(
		'post_type'      => HHELP_CPT,
		'post_status'    => 'any',
		'posts_per_page' => -1,
		'fields'         => 'ids',
	)
);
foreach ( $ids as $id ) {
	if ( in_array( (int) $id, $featured_on, true ) ) {
		update_post_meta( (int) $id, '_hhelp_featured', 1 );
	} else {
		delete_post_meta( (int) $id, '_hhelp_featured' );
	}
}

if ( class_exists( 'Hhelp_Tree' ) ) {
	Hhelp_Tree::flush_cache();
}
wp_cache_flush();

echo "updated={$ok} missing={$miss} featured=" . implode( ',', $featured_on ) . "\n";
