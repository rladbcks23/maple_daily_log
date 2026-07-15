import 'package:flutter/material.dart';

import 'api_client.dart';

void main() {
  runApp(const MapleTaskReminderApp());
}

class MapleTaskReminderApp extends StatelessWidget {
  const MapleTaskReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '메이플 숙제알리미',
      theme: ThemeData(
        fontFamily: 'Malgun Gothic',
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: const NexonLoginPage(),
    );
  }
}

class AppColors {
  static const background = Color(0xFFF5F6F9);
  static const border = Color(0xFFE6E8EF);
  static const text = Color(0xFF3D4048);
  static const muted = Color(0xFF7B8291);
  static const primary = Color(0xFF5E76B7);
  static const button = Color(0xFF3D4048);
}

class NexonLoginPage extends StatefulWidget {
  const NexonLoginPage({super.key});

  @override
  State<NexonLoginPage> createState() => _NexonLoginPageState();
}

class _NexonLoginPageState extends State<NexonLoginPage> {
  final ApiClient apiClient = ApiClient();

  var isLoading = false;
  String? errorMessage;
  List<NexonCharacterSummary> characters = const [];

  Future<void> loadCharacters() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loadedCharacters = await apiClient.fetchNexonCharacters();
      if (!mounted) {
        return;
      }
      setState(() {
        characters = loadedCharacters;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _LoginBrand(),
              const SizedBox(height: 28),
              _LoginCard(
                isLoading: isLoading,
                characterCount: characters.length,
                errorMessage: errorMessage,
                onLogin: loadCharacters,
              ),
              if (characters.isNotEmpty) ...[
                const SizedBox(height: 18),
                _CharacterPreviewList(characters: characters),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'M',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '메이플 숙제알리미',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '놓친 숙제, 이제 안 놓치게',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.isLoading,
    required this.characterCount,
    required this.errorMessage,
    required this.onLogin,
  });

  final bool isLoading;
  final int characterCount;
  final String? errorMessage;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '넥슨 계정의 캐릭터 목록을\n서버 API로 불러옵니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: isLoading ? null : onLogin,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.button,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '넥슨 계정 캐릭터 불러오기',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          if (characterCount > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$characterCount명의 캐릭터를 불러왔어요.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFB85F47),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CharacterPreviewList extends StatelessWidget {
  const _CharacterPreviewList({required this.characters});

  final List<NexonCharacterSummary> characters;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(10),
        itemCount: characters.length,
        separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, index) {
          final character = characters[index];
          final description = [
            character.worldName,
            character.characterClass,
            if (character.characterLevel != null) 'Lv.${character.characterLevel}',
          ].where((value) => value.isNotEmpty).join(' · ');

          return ListTile(
            dense: true,
            title: Text(
              character.characterName.isEmpty ? '이름 없음' : character.characterName,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: description.isEmpty
                ? null
                : Text(
                    description,
                    style: const TextStyle(color: AppColors.muted),
                  ),
          );
        },
      ),
    );
  }
}
