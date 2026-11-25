import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/agent/agent_config.dart';

void main() {
  test('trợ lý Claude chưa chọn model: mặc định Sonnet; Opus / Fable là model đắt', () {
    const claude = AgentOptions('claude', ['claude-opus-5-5', 'claude-fable-5-1', 'claude-sonnet-5-5', 'claude-haiku-5-5'], ['low', 'high'], 'claude-opus-5-5', 'high');
    expect(sonnetModelOf(claude), 'claude-sonnet-5-5');
    expect(sonnetModelOf(const AgentOptions('claude', ['opus', 'sonnet'], ['high'], 'opus', 'high')), 'sonnet');
    expect(sonnetModelOf(const AgentOptions('codex', ['gpt-6.1-sol'], ['high'], 'gpt-6.1-sol', 'high')), isNull);
    expect(isPremiumModel('claude-opus-5-5'), isTrue);
    expect(isPremiumModel('claude-fable-5-1'), isTrue);
    expect(isPremiumModel('claude-sonnet-5-5'), isFalse);
  });
}
