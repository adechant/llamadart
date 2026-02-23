part of 'coding_agent_tui.dart';

extension _CodingAgentTuiMenuDialogView on _CodingAgentTuiState {
  Component _buildTopMenuBar() {
    final menuChildren = <Component>[
      Container(
        padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
        child: Text(
          '≡',
          style: TextStyle(
            color: _turboMenuMnemonic,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ];

    for (var i = 0; i < _topMenus.length; i++) {
      final menu = _topMenus[i];
      final selected = _openTopMenuIndex == i;
      menuChildren.add(
        GestureDetector(
          onTap: () => _toggleTopMenu(i),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: selected ? _turboMenuSelectionBackground : _turboMenuBar,
            ),
            child: _buildTurboMenuLabel(menu: menu, selected: selected),
          ),
        ),
      );
      if (i < _topMenus.length - 1) {
        menuChildren.add(SizedBox(width: 1));
      }
    }

    menuChildren.add(
      Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openTopMenuIndex == null ? null : _closeTopMenu,
          child: SizedBox(height: 1),
        ),
      ),
    );

    return Container(
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: _turboMenuBar,
        border: BoxBorder(bottom: BorderSide(color: _turboDialogBorderLight)),
      ),
      child: Row(children: menuChildren),
    );
  }

  Component _buildTurboMenuLabel({
    required _TopMenu menu,
    required bool selected,
  }) {
    final label = menu.label;
    final mnemonic = menu.mnemonic;
    final lowerLabel = label.toLowerCase();
    final lowerMnemonic = mnemonic.toLowerCase();
    final mnemonicIndex = lowerLabel.indexOf(lowerMnemonic);

    final baseStyle = TextStyle(
      color: _turboMenuText,
      fontWeight: FontWeight.bold,
    );

    if (mnemonicIndex < 0 || mnemonicIndex >= label.length) {
      return Text(' $label ', style: baseStyle);
    }

    final before = label.substring(0, mnemonicIndex);
    final marker = label.substring(mnemonicIndex, mnemonicIndex + 1);
    final after = label.substring(mnemonicIndex + 1);

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: <InlineSpan>[
          TextSpan(text: ' $before'),
          TextSpan(
            text: marker,
            style: TextStyle(
              color: selected ? _turboMenuText : _turboMenuMnemonic,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: '$after '),
        ],
      ),
    );
  }

  Component _buildTopMenuDropdownOverlay() {
    final menuIndex = _openTopMenuIndex;
    if (menuIndex == null) {
      return SizedBox(height: 0);
    }

    final menu = _topMenus[menuIndex];
    final left = _menuPopupLeft(menuIndex).toDouble();
    final width = _menuPopupWidth(menu).toDouble();

    final items = <Component>[];
    final menuContentWidth = _menuPopupContentWidth(menu);
    final menuShortcutWidth = _menuPopupShortcutWidth(menu);
    for (var i = 0; i < menu.items.length; i++) {
      final item = menu.items[i];
      if (item.isSeparator) {
        items.add(
          Container(
            padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
            decoration: BoxDecoration(color: _turboMenuBar),
            child: Text(
              _repeatMenuRule(menuContentWidth),
              style: TextStyle(color: _turboMenuBorder),
            ),
          ),
        );
        continue;
      }

      final selected = _openTopMenuItemIndex == i;
      items.add(
        GestureDetector(
          onTap: () => _runTopMenuCommand(item.command),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
            decoration: BoxDecoration(
              color: selected ? _turboMenuSelectionBackground : _turboMenuBar,
            ),
            child: Row(
              children: <Component>[
                Expanded(
                  child: _buildTurboPopupItemLabel(
                    label: item.label,
                    selected: selected,
                  ),
                ),
                if (menuShortcutWidth > 0)
                  Text(
                    item.shortcut.padLeft(menuShortcutWidth),
                    style: TextStyle(
                      color: _turboMenuText,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: left,
      top: 2,
      child: SizedBox(
        width: width + 1,
        child: Container(
          color: _turboDialogShadow,
          padding: EdgeInsets.only(right: 1, bottom: 1),
          child: SizedBox(
            width: width,
            child: Container(
              decoration: BoxDecoration(
                color: _turboMenuBar,
                border: BoxBorder.all(color: _turboMenuBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items,
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _menuPopupLeft(int menuIndex) {
    var left = 2;
    for (var i = 0; i < menuIndex; i++) {
      left += _topMenus[i].label.length + 3;
    }
    return left;
  }

  int _menuPopupLabelWidth(_TopMenu menu) {
    var width = 0;
    for (final item in menu.items) {
      if (item.label.length > width) {
        width = item.label.length;
      }
    }
    return width;
  }

  int _menuPopupShortcutWidth(_TopMenu menu) {
    var width = 0;
    for (final item in menu.items) {
      if (item.shortcut.length > width) {
        width = item.shortcut.length;
      }
    }
    return width;
  }

  int _menuPopupWidth(_TopMenu menu) {
    return _menuPopupLabelWidth(menu) + _menuPopupShortcutWidth(menu) + 4;
  }

  int _menuPopupContentWidth(_TopMenu menu) {
    return _menuPopupWidth(menu) - 4;
  }

  Component _buildTurboPopupItemLabel({
    required String label,
    required bool selected,
  }) {
    if (label.isEmpty) {
      return Text('');
    }

    final marker = label.substring(0, 1);
    final rest = label.substring(1);

    return RichText(
      text: TextSpan(
        style: TextStyle(color: _turboMenuText, fontWeight: FontWeight.bold),
        children: <InlineSpan>[
          TextSpan(
            text: marker,
            style: TextStyle(
              color: selected ? _turboMenuText : _turboMenuMnemonic,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: rest),
        ],
      ),
    );
  }

  String _repeatMenuRule(int width) {
    if (width <= 0) {
      return '';
    }
    return List<String>.filled(width, '-').join();
  }

  Component _buildExitConfirmationOverlay() {
    final prompt = _busy
        ? 'Generation running. Exit?'
        : 'Exit llamadart agent?';
    final enterTarget = _exitConfirmChoice == _ExitChoice.yes ? 'YES' : 'NO';

    return Center(
      child: SizedBox(
        width: 46,
        child: Container(
          color: _turboDialogShadow,
          padding: EdgeInsets.only(right: 1, bottom: 1),
          child: Container(
            decoration: BoxDecoration(
              color: _turboDialogBody,
              border: BoxBorder.all(color: _turboDialogBorderLight),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Component>[
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                  decoration: BoxDecoration(
                    color: _turboDialogTitleBar,
                    border: BoxBorder(
                      bottom: BorderSide(color: _turboDialogBorderLight),
                    ),
                  ),
                  child: Row(
                    children: <Component>[
                      Text(
                        '[■] Confirm Exit',
                        style: TextStyle(
                          color: Colors.brightWhite,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
                      Text('[ ]', style: TextStyle(color: _turboDialogBody)),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                  child: Text(
                    prompt,
                    style: TextStyle(
                      color: _turboDialogText,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Component>[
                      _buildExitChoiceButton(
                        label: ' YES ',
                        selected: _exitConfirmChoice == _ExitChoice.yes,
                      ),
                      SizedBox(width: 1),
                      _buildExitChoiceButton(
                        label: ' NO ',
                        selected: _exitConfirmChoice == _ExitChoice.no,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                  decoration: BoxDecoration(
                    color: _turboDialogBody,
                    border: BoxBorder(
                      top: BorderSide(color: _turboDialogBorderDark),
                    ),
                  ),
                  child: Text(
                    'Enter=$enterTarget  Esc=NO  <-/-> choose',
                    style: TextStyle(color: _turboDialogTextDim),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Component _buildExitChoiceButton({
    required String label,
    required bool selected,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
      decoration: BoxDecoration(
        color: selected ? _turboWindowSelectionBackground : _turboDialogBody,
        border: BoxBorder.all(
          color: selected ? _turboDialogBorderDark : _turboDialogBorderLight,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.black : _turboDialogText,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
