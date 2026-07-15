import 'package:characters/characters.dart';
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
      home: const MapleAppShell(),
    );
  }
}

class AppColors {
  static const background = Color(0xFFF7F8FB);
  static const sidebar = Color(0xFFFBF8EF);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE6E8EF);
  static const text = Color(0xFF343741);
  static const muted = Color(0xFF7B8291);
  static const primary = Color(0xFF5E76B7);
  static const selected = Color(0xFFEAF0FF);
  static const button = Color(0xFF3D4048);
  static const disabled = Color(0xFFB8BEC9);
}

enum AppSection {
  character('캐릭터 선택', Icons.person_add_alt_1_rounded),
  scheduler('스케쥴러', Icons.event_note_rounded),
  events('진행중인 이벤트', Icons.celebration_rounded),
  notices('공지사항', Icons.campaign_rounded),
  sunday('이번주 썬데이', Icons.wb_sunny_rounded);

  const AppSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class MapleAppShell extends StatefulWidget {
  const MapleAppShell({super.key});

  @override
  State<MapleAppShell> createState() => _MapleAppShellState();
}

class _MapleAppShellState extends State<MapleAppShell> {
  final ApiClient apiClient = ApiClient();

  var currentSection = AppSection.character;
  var isLoading = false;
  String? errorMessage;
  NexonCharacterSummary? selectedCharacter;

  Future<void> openCharacterPicker() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final characters = await apiClient.fetchNexonCharacters();
      if (!mounted) {
        return;
      }

      final selected = await showModalBottomSheet<NexonCharacterSummary>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return _CharacterPickerSheet(
            characters: characters,
            selectedCharacter: selectedCharacter,
          );
        },
      );

      if (selected != null && mounted) {
        setState(() {
          selectedCharacter = selected;
        });
      }
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

  void selectSection(AppSection section) {
    if (section != AppSection.character && selectedCharacter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('캐릭터를 먼저 선택해주세요.')),
      );
      return;
    }

    setState(() {
      currentSection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _AppSidebar(
            currentSection: currentSection,
            selectedCharacter: selectedCharacter,
            onAddCharacter: () => selectSection(AppSection.character),
            onSelectSection: selectSection,
          ),
          Expanded(
            child: _MainPanel(
              currentSection: currentSection,
              selectedCharacter: selectedCharacter,
              isLoading: isLoading,
              errorMessage: errorMessage,
              onAddCharacter: openCharacterPicker,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppSidebar extends StatelessWidget {
  const _AppSidebar({
    required this.currentSection,
    required this.selectedCharacter,
    required this.onAddCharacter,
    required this.onSelectSection,
  });

  final AppSection currentSection;
  final NexonCharacterSummary? selectedCharacter;
  final VoidCallback onAddCharacter;
  final ValueChanged<AppSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final hasCharacter = selectedCharacter != null;

    return Container(
      width: 264,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: Color(0xFFE3DED1))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SidebarBrand(),
              const SizedBox(height: 24),
              _SidebarCharacterButton(
                selectedCharacter: selectedCharacter,
                onPressed: onAddCharacter,
              ),
              const SizedBox(height: 14),
              const Divider(color: Color(0xFFE3DED1)),
              const SizedBox(height: 8),
              for (final section in AppSection.values)
                if (section != AppSection.character)
                  _SidebarNavItem(
                    section: section,
                    selected: currentSection == section,
                    enabled: hasCharacter,
                    onPressed: () => onSelectSection(section),
                  ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'M',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '메이플 숙제알리미',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '놓친 숙제, 이제 안 놓치게',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarCharacterButton extends StatelessWidget {
  const _SidebarCharacterButton({
    required this.selectedCharacter,
    required this.onPressed,
  });

  final NexonCharacterSummary? selectedCharacter;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final character = selectedCharacter;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  character == null
                      ? Icons.person_add_alt_1_rounded
                      : Icons.check_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character == null
                          ? '캐릭터 추가'
                          : _displayCharacterName(character),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      character == null
                          ? '먼저 알림 대상을 선택'
                          : _characterDescription(character),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.section,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final AppSection section;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.disabled
        : selected
            ? AppColors.primary
            : AppColors.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected && enabled ? AppColors.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(section.icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (!enabled)
                  const Icon(
                    Icons.lock_rounded,
                    size: 15,
                    color: AppColors.disabled,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    required this.currentSection,
    required this.selectedCharacter,
    required this.isLoading,
    required this.errorMessage,
    required this.onAddCharacter,
  });

  final AppSection currentSection;
  final NexonCharacterSummary? selectedCharacter;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onAddCharacter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 26, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    currentSection.label,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onAddCharacter,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(selectedCharacter == null ? '캐릭터 추가' : '캐릭터 변경'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: currentSection == AppSection.character
                  ? _CharacterSelectPanel(
                      selectedCharacter: selectedCharacter,
                      isLoading: isLoading,
                      errorMessage: errorMessage,
                      onAddCharacter: onAddCharacter,
                    )
                  : _LockedFeaturePanel(
                      section: currentSection,
                      selectedCharacter: selectedCharacter,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterSelectPanel extends StatelessWidget {
  const _CharacterSelectPanel({
    required this.selectedCharacter,
    required this.isLoading,
    required this.errorMessage,
    required this.onAddCharacter,
  });

  final NexonCharacterSummary? selectedCharacter;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onAddCharacter;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                selectedCharacter == null
                    ? '알림을 받을 캐릭터를 선택해주세요.'
                    : '현재 알림 대상 캐릭터',
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                selectedCharacter == null
                    ? '캐릭터를 선택하면 스케쥴러, 이벤트, 공지사항 화면을 사용할 수 있어요.'
                    : '이 캐릭터 기준으로 숙제 알림과 콘텐츠 조회를 진행합니다.',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              if (selectedCharacter != null) ...[
                const SizedBox(height: 18),
                _SelectedCharacterCard(character: selectedCharacter!),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: isLoading ? null : onAddCharacter,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_search_rounded, size: 18),
                label: Text(selectedCharacter == null ? '캐릭터 추가' : '캐릭터 변경'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.button,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFB85F47),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedFeaturePanel extends StatelessWidget {
  const _LockedFeaturePanel({
    required this.section,
    required this.selectedCharacter,
  });

  final AppSection section;
  final NexonCharacterSummary? selectedCharacter;

  @override
  Widget build(BuildContext context) {
    if (selectedCharacter == null) {
      return const _BlockedPanel();
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.label,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_displayCharacterName(selectedCharacter!)} 기준 데이터 연결을 준비 중입니다.',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockedPanel extends StatelessWidget {
  const _BlockedPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_rounded, color: AppColors.disabled, size: 28),
          SizedBox(height: 12),
          Text(
            '캐릭터 선택이 필요해요.',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '왼쪽의 캐릭터 추가를 눌러 알림 대상 캐릭터를 먼저 선택해주세요.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedCharacterCard extends StatelessWidget {
  const _SelectedCharacterCard({required this.character});

  final NexonCharacterSummary character;

  @override
  Widget build(BuildContext context) {
    final description = _characterDescription(character);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8E0FF)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.check_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayCharacterName(character),
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterPickerSheet extends StatelessWidget {
  const _CharacterPickerSheet({
    required this.characters,
    required this.selectedCharacter,
  });

  final List<NexonCharacterSummary> characters;
  final NexonCharacterSummary? selectedCharacter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '캐릭터 선택',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '닫기',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (characters.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  '불러온 캐릭터가 없어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: characters.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final character = characters[index];
                    final selected =
                        _isSameCharacter(character, selectedCharacter);

                    return _CharacterPickerTile(
                      character: character,
                      selected: selected,
                      onTap: () => Navigator.of(context).pop(character),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CharacterPickerTile extends StatelessWidget {
  const _CharacterPickerTile({
    required this.character,
    required this.selected,
    required this.onTap,
  });

  final NexonCharacterSummary character;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final description = _characterDescription(character);

    return Material(
      color: selected ? AppColors.selected : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : const Color(0xFFF0F2F7),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  character.characterName.isEmpty
                      ? '?'
                      : character.characterName.characters.first,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayCharacterName(character),
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _displayCharacterName(NexonCharacterSummary character) {
  return character.characterName.isEmpty ? '이름 없음' : character.characterName;
}

String _characterDescription(NexonCharacterSummary character) {
  return [
    character.worldName,
    character.characterClass,
    if (character.characterLevel != null) 'Lv.${character.characterLevel}',
  ].where((value) => value.isNotEmpty).join(' · ');
}

bool _isSameCharacter(
  NexonCharacterSummary character,
  NexonCharacterSummary? other,
) {
  if (other == null) {
    return false;
  }

  if (character.ocid.isNotEmpty && other.ocid.isNotEmpty) {
    return character.ocid == other.ocid;
  }

  return character.characterName == other.characterName &&
      character.worldName == other.worldName;
}
