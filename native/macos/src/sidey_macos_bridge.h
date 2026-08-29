#ifndef SIDEY_MACOS_BRIDGE_H
#define SIDEY_MACOS_BRIDGE_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <vector>

namespace sidey {

class SideyMacOSBridge : public godot::Node {
	GDCLASS(SideyMacOSBridge, godot::Node)

public:
	SideyMacOSBridge();
	~SideyMacOSBridge() override;

	godot::Dictionary capability_report() const;

	godot::Error keychain_store(const godot::String &account, const godot::String &secret);
	godot::String keychain_read(const godot::String &account) const;
	godot::Error keychain_delete(const godot::String &account);

	double get_idle_seconds() const;
	bool is_screen_locked() const;

	godot::Error register_default_hotkeys();
	void unregister_hotkeys();

	godot::Error set_overlay_runtime_mode(bool enabled);
	godot::Error set_all_spaces_window_policy(bool enabled);
	godot::Error set_ignores_mouse_events(bool enabled);
	godot::Error set_launch_at_login(bool enabled);
	bool is_launch_at_login_enabled() const;
	void set_local_enter_monitor_enabled(bool enabled);

	void dispatch_hotkey(int hotkey_id);
	void dispatch_local_enter(bool shift_pressed);

protected:
	static void _bind_methods();
	void _notification(int what);

private:
	void register_workspace_observers();
	void unregister_workspace_observers();
	void register_local_key_monitor();
	void unregister_local_key_monitor();
	void emit_screen_lock(bool locked);
	void emit_system_sleep(bool sleeping);
	void *native_window() const;

	bool screen_locked_ = false;
	bool sleeping_ = false;
	bool local_enter_monitor_enabled_ = false;
	void *observer_tokens_ = nullptr;
	void *local_key_monitor_ = nullptr;
	void *hotkey_handler_ = nullptr;
	std::vector<void *> hotkey_refs_;
};

} // namespace sidey

#endif // SIDEY_MACOS_BRIDGE_H
