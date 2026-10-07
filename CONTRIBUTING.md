# 参与贡献 / Contributing

欢迎通过 [Issues](https://github.com/Liu-Da/desk-ctrl/issues) 报告问题和兼容性，通过 Pull Request 提交改进。

## 开发与检查

使用 macOS 和 Swift 6 工具链。无需安装第三方包。

```sh
./scripts/check.sh
./scripts/build.sh
codesign --verify --deep --strict "dist/Desk Control.app"
```

改动打包脚本时，再运行 `./scripts/package-dmg.sh`。应用最低运行版本是 macOS 13；测试工具链自身的运行要求可能更高。

- 协议、目标高度、停止监测和本机存储的改动，请补充对应的 `DeskCoreTests`。
- 蓝牙和运动控制的改动，请说明已完成的实机验证、面板型号和未验证的行为。
- 界面改动请提供截图和操作说明。实机测试移动时确保桌面周围有足够空间，并能操作物理面板。
- Issue 请包含应用版本、macOS 版本、Mac 架构、面板型号、复现步骤，以及预期和实际结果。公开诊断前移除不希望公开的桌子名称、UUID、收藏等信息。

## English

Use macOS with a Swift 6 toolchain. Run the checks above before submitting a pull request. Changes to protocol handling, motion guards, or local storage should include relevant core tests. For Bluetooth or movement changes, state which panel was tested and which behavior remains unverified. Add screenshots for UI changes.

Bug reports should include the app and macOS versions, Mac architecture, panel model, reproduction steps, and expected and actual behavior. Remove private device identifiers and preferences from diagnostics before publishing them.
