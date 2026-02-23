part of 'coding_agent_tui.dart';

extension _CodingAgentTuiMenuDialogView on _CodingAgentTuiState {
  Component _buildTopMenuBar() {
    final menuChildren = <Component>[];
    for (var i = 0; i < _topMenus.length; i++) {
      final menu = _topMenus[i];
      final selected = _openTopMenuIndex == i;
      menuChildren.add(
        Container(
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: selected ? _turboMenuSelectionBackground : _turboMenuBar,
          ),
          child: _buildTurboMenuLabel(menu: menu, selected: selected),
        ),
      );
      if (i < _topMenus.length - 1) {
        menuChildren.add(SizedBox(width: 1));
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
      decoration: BoxDecoration(
        color: _turboMenuBar,
        border: BoxBorder(bottom: BorderSide(color: Colors.brightWhite)),
      ),
      child: Row(
        children: <Component>[
          Text(
            '::',
            style: TextStyle(
              color: _turboMenuMnemonic,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 1),
          ...menuChildren,
        ],
      ),
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
      color: selected ? Colors.brightWhite : _turboMenuText,
      fontWeight: FontWeight.bold,
    );

    if (mnemonicIndex < 0 || mnemonicIndex >= label.length) {
      return Text(label, style: baseStyle);
    }

    final before = label.substring(0, mnemonicIndex);
    final marker = label.substring(mnemonicIndex, mnemonicIndex + 1);
    final after = label.substring(mnemonicIndex + 1);

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: <InlineSpan>[
          TextSpan(text: before),
          TextSpan(
            text: marker,
            style: TextStyle(
              color: selected ? Colors.brightYellow : _turboMenuMnemonic,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: after),
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
    for (var i = 0; i < menu.items.length; i++) {
      final item = menu.items[i];
      final selected = _openTopMenuItemIndex == i;
      final line =
          ' ${item.label.padRight(_menuPopupLabelWidth(menu))}  ${item.shortcut.padLeft(_menuPopupShortcutWidth(menu))} ';
      items.add(
        Container(
          padding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          decoration: BoxDecoration(
            color: selected ? _turboMenuSelectionBackground : _turboMenuBar,
          ),
          child: Text(
            line,
            style: TextStyle(
              color: selected ? Colors.brightWhite : _turboMenuText,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: left,
      top: 1,
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
    var left = 4;
    for (var i = 0; i < menuIndex; i++) {
      left += _topMenus[i].label.length + 1;
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
    return _menuPopupLabelWidth(menu) + _menuPopupShortcutWidth(menu) + 5;
  }

  Component _buildExitConfirmationOverlay() {
    final prompt = _busy
        ? 'Generation running. Exit?'
        : 'Exit llamadart agent?';
    final enterTarget = _exitConfirmChoice == _ExitChoice.yes ? 'YES' : 'NO';

    return Center(
      child: SizedBox(
        width: 42,
        child: Container(
          color: _turboDialogShadow,
          padding: EdgeInsets.only(right: 1, bottom: 1),
          child: Container(
            decoration: BoxDecoration(
              color: _turboDialogBody,
              border: BoxBorder.all(color: _turboDialogBorderDark),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Component>[
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                  decoration: BoxDecoration(
                    color: _turboDialogTitleBar,
                    border: BoxBorder(
                      bottom: BorderSide(color: _turboDialogBorderDark),
                    ),
                  ),
                  child: Row(
                    children: <Component>[
                      Text(
                        ' Confirm Exit ',
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
                    style: TextStyle(color: _turboDialogText),
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
                      top: BorderSide(color: _turboDialogBorderLight),
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
        color: selected ? _turboDialogTitleBar : _turboDialogBody,
        border: BoxBorder.all(
          color: selected ? _turboDialogBorderLight : _turboDialogBorderDark,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.brightWhite : _turboDialogText,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
