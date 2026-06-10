# bim.nvim

**bim.nvim** is a Neovim plugin that enhances insert-mode keymapping by showing typed keys **in real time**, without waiting for `timeoutlen`. It provides a responsive and intuitive insert-mode experience, ideal for complex input workflows like ime.

---

## ✨ Features

- 🔁 **Real-time key echoing**: Immediately shows each typed character in the buffer.
- ⏱️ **No keymap timeout delays**: Avoids `timeoutlen` lag by resolving mappings proactively.
- ♻️ **State restoration**: Automatically restores and replaces text if a valid mapped sequence is completed.

---

## 📸 Screenshot

https://github.com/user-attachments/assets/7320d380-7360-45d9-84bd-c110dd3401ff

## 📦 Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "sontungexpt/bim.nvim",
  event = "InsertEnter",
  opts = {},
}
```

## 🛠️ How to use

1. **Install the plugin** using your preferred Neovim package manager.
2. **Maps by vim.keymap.set**
3. **Enter insert mode** and start typing. The plugin will echo your keys in real time.

## 📜 License

This project is licensed under the **Apache Licence 2.0** [LICENCE](./LICENSE)

```

```
