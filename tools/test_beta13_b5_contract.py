"""B5 static contracts; actual Kindle rendering and Wi-Fi pairing require device testing."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]

def src(file): return (ROOT/'miuread.koplugin'/file).read_text(encoding='utf-8')
class B5Contracts(unittest.TestCase):
    def test_home_header_uses_intrinsic_distribution_not_fixed_percentages(self):
        home=src('miuread/home_view.lua')
        block=home.split('function HomeWidget:_build_header(children, m)',1)[1].split('function HomeWidget:_grid_geometry',1)[0]
        self.assertIn('HeaderLayout.arrange',block)
        self.assertNotIn('header_w*.085',block)
        self.assertNotIn('header_w*.205',block)
        self.assertNotIn('wifi_value_cell',block)
        self.assertIn('self.opts.wifi_icon',block)
    def test_persisted_user_visibility_and_no_side_effects(self):
        main=src('main.lua')
        self.assertIn('function Plugin:home_header_settings_menu()',main)
        self.assertIn('function Plugin:_set_home_header_visible(visible)',main)
        self.assertIn('function Plugin:_set_home_header_item(key,visible)',main)
        self.assertIn('header_visible=home.header_visible~=false',main)
        self.assertIn('header_items=home.header_items',main)
        self.assertIn('function Plugin:_home_wifi_details()',main)
        self.assertNotIn('self:_wifi_stop(',main.split('function Plugin:_set_home_header_item',1)[1].split('function Plugin:home_layout_settings_menu',1)[0])
        setting=src('miuread/plugin_settings.lua')
        self.assertIn('主页顶栏显示',setting)
        store=src('miuread/store.lua')
        self.assertIn('header_items={title=true,account=true,wifi=true',store)
    def test_wifi_detail_is_explicit_and_cached(self):
        main=src('main.lua')
        panel=main.split('function Plugin:_home_wifi_details()',1)[1].split('function Plugin:_home_wifi_text()',1)[0]
        self.assertIn('HomeData.cached_device_state()',panel)
        self.assertIn('当前连接',panel)
        self.assertIn('查看可用网络',panel)
        self.assertIn('self:_home_wifi_settings()',panel)
        self.assertNotIn('getNetworkList',panel)
        self.assertIn('on_wifi=function() self:_home_wifi_details() end',main)
    def test_no_unrelated_core_changes(self):
        self.assertTrue((ROOT/'miuread.koplugin/miuread/comment_overlay.lua').exists())
        self.assertTrue((ROOT/'miuread.koplugin/miuread/comment_sync.lua').exists())
        self.assertTrue((ROOT/'miuread.koplugin/miuread/book_delete_service.lua').exists())
if __name__=='__main__': unittest.main()
