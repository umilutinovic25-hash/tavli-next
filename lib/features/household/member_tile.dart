import 'package:flutter/material.dart';

import '../../domain/household.dart';
import '../../domain/household_role.dart';

/// Radnje vlasnika nad drugim članom.
enum MemberAction { remove }

/// Ime člana kako ga vide ostali.
String memberName(HouseholdMember m) => m.displayName ?? 'Član bez imena';

/// Red člana: ime, uloga, „Ti“ i (za vlasnika) meni radnji.
class MemberTile extends StatelessWidget {
  const MemberTile({
    super.key,
    required this.member,
    required this.isSelf,
    required this.canManage,
    required this.onAction,
  });

  final HouseholdMember member;
  final bool isSelf;
  final bool canManage;
  final ValueChanged<MemberAction> onAction;

  @override
  Widget build(BuildContext context) {
    final role = member.role == HouseholdRole.owner ? 'Vlasnik' : 'Član';
    final name = memberName(member);
    return MergeSemantics(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          member.role == HouseholdRole.owner
              ? Icons.star_outline
              : Icons.person_outline,
        ),
        title: Text(name),
        subtitle: Text(role),
        trailing: isSelf
            ? const Chip(label: Text('Ti'))
            : canManage
            ? PopupMenuButton<MemberAction>(
                onSelected: onAction,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: MemberAction.remove,
                    child: Text('Ukloni iz domaćinstva'),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
