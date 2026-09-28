/* @ds-bundle: {"format":4,"namespace":"ApplkeDesignSystem_795038","components":[{"name":"Badge","sourcePath":"components/display/Badge.jsx"},{"name":"Card","sourcePath":"components/display/Card.jsx"},{"name":"Tag","sourcePath":"components/display/Tag.jsx"},{"name":"Dialog","sourcePath":"components/feedback/Dialog.jsx"},{"name":"Toast","sourcePath":"components/feedback/Toast.jsx"},{"name":"Tooltip","sourcePath":"components/feedback/Tooltip.jsx"},{"name":"Button","sourcePath":"components/forms/Button.jsx"},{"name":"Checkbox","sourcePath":"components/forms/Checkbox.jsx"},{"name":"IconButton","sourcePath":"components/forms/IconButton.jsx"},{"name":"Input","sourcePath":"components/forms/Input.jsx"},{"name":"Radio","sourcePath":"components/forms/Radio.jsx"},{"name":"Select","sourcePath":"components/forms/Select.jsx"},{"name":"Switch","sourcePath":"components/forms/Switch.jsx"},{"name":"Icon","sourcePath":"components/icon/Icon.jsx"},{"name":"Tabs","sourcePath":"components/navigation/Tabs.jsx"}],"sourceHashes":{"components/display/Badge.jsx":"b73b365edca3","components/display/Card.jsx":"de058aef37ab","components/display/Tag.jsx":"2877aaad747f","components/feedback/Dialog.jsx":"4b2cf1e5c76e","components/feedback/Toast.jsx":"259678743387","components/feedback/Tooltip.jsx":"cf7bbc1f9460","components/forms/Button.jsx":"c2760e59d7d3","components/forms/Checkbox.jsx":"0f7d545c8a61","components/forms/IconButton.jsx":"e101d0eb4cd1","components/forms/Input.jsx":"8d6bcd9451e7","components/forms/Radio.jsx":"d435392f2c1f","components/forms/Select.jsx":"cee50a66b6f4","components/forms/Switch.jsx":"42a7baeb80db","components/icon/Icon.jsx":"0ebf7395c258","components/navigation/Tabs.jsx":"8016da9d8811","ui_kits/workspace/App.jsx":"8b34e104ba2f","ui_kits/workspace/ProjectsView.jsx":"3684a33af7e9","ui_kits/workspace/SettingsView.jsx":"8b2f3ce1333a","ui_kits/workspace/Sidebar.jsx":"78d1eb09027e","ui_kits/workspace/Topbar.jsx":"4eea60f450d9","ui_kits/workspace/doc-page.js":"371bab66f42d"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.ApplkeDesignSystem_795038 = window.ApplkeDesignSystem_795038 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/display/Badge.jsx
try { (() => {
const TONES = {
  neutral: {
    bg: "var(--surface-sunken)",
    fg: "var(--text-secondary)"
  },
  accent: {
    bg: "var(--accent-soft)",
    fg: "var(--accent-active)"
  },
  success: {
    bg: "var(--success-soft)",
    fg: "var(--green-600)"
  },
  warning: {
    bg: "var(--warning-soft)",
    fg: "var(--amber-600)"
  },
  danger: {
    bg: "var(--danger-soft)",
    fg: "var(--red-600)"
  }
};
function Badge({
  children,
  tone = "neutral",
  dot = false,
  style
}) {
  const t = TONES[tone];
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 5,
      background: t.bg,
      color: t.fg,
      fontSize: "var(--text-xs)",
      fontWeight: "var(--weight-medium)",
      letterSpacing: "var(--tracking)",
      padding: "2px 8px",
      borderRadius: "var(--radius-pill)",
      fontFamily: "var(--font-sans)",
      lineHeight: 1.4,
      whiteSpace: "nowrap",
      ...style
    }
  }, dot && /*#__PURE__*/React.createElement("span", {
    style: {
      width: 6,
      height: 6,
      borderRadius: "var(--radius-pill)",
      background: t.fg
    }
  }), children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/Badge.jsx", error: String((e && e.message) || e) }); }

// components/display/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
function Card({
  children,
  padding = "var(--pad-card)",
  interactive = false,
  elevated = false,
  style,
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", _extends({
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      background: "var(--surface-card)",
      border: "1px solid var(--border-subtle)",
      borderRadius: "var(--radius-card)",
      boxShadow: elevated ? "var(--shadow-raised)" : interactive && hover ? "var(--shadow-card)" : "var(--shadow-none)",
      padding,
      boxSizing: "border-box",
      transition: "box-shadow 140ms ease, border-color 140ms ease, transform 120ms ease",
      cursor: interactive ? "pointer" : "default",
      transform: interactive && hover ? "translateY(-1px)" : "none",
      borderColor: interactive && hover ? "var(--border-default)" : "var(--border-subtle)",
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)",
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/Card.jsx", error: String((e && e.message) || e) }); }

// components/display/Tag.jsx
try { (() => {
function Tag({
  children,
  onRemove,
  leadingIcon,
  style
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 6,
      background: "var(--surface-card)",
      color: "var(--text-primary)",
      border: "1px solid var(--border-default)",
      fontSize: "var(--text-sm)",
      letterSpacing: "var(--tracking)",
      padding: "3px 8px",
      borderRadius: "var(--radius-xs)",
      fontFamily: "var(--font-sans)",
      lineHeight: 1.4,
      whiteSpace: "nowrap",
      ...style
    }
  }, leadingIcon, children, onRemove && /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": "Remove",
    onClick: onRemove,
    style: {
      display: "inline-flex",
      background: "none",
      border: "none",
      padding: 0,
      cursor: "pointer",
      color: "var(--text-tertiary)"
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "12",
    height: "12",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "2.2",
    strokeLinecap: "round"
  }, /*#__PURE__*/React.createElement("line", {
    x1: "18",
    y1: "6",
    x2: "6",
    y2: "18"
  }), /*#__PURE__*/React.createElement("line", {
    x1: "6",
    y1: "6",
    x2: "18",
    y2: "18"
  }))));
}
Object.assign(__ds_scope, { Tag });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/Tag.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Toast.jsx
try { (() => {
const ICONS = {
  success: {
    color: "var(--success)",
    path: /*#__PURE__*/React.createElement("polyline", {
      points: "20 6 9 17 4 12"
    })
  },
  danger: {
    color: "var(--danger)",
    path: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("line", {
      x1: "18",
      y1: "6",
      x2: "6",
      y2: "18"
    }), /*#__PURE__*/React.createElement("line", {
      x1: "6",
      y1: "6",
      x2: "18",
      y2: "18"
    }))
  },
  info: {
    color: "var(--accent)",
    path: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("line", {
      x1: "12",
      y1: "16",
      x2: "12",
      y2: "12"
    }), /*#__PURE__*/React.createElement("line", {
      x1: "12",
      y1: "8",
      x2: "12.01",
      y2: "8"
    }))
  }
};
function Toast({
  title,
  message,
  tone = "info",
  onDismiss,
  style
}) {
  const icon = ICONS[tone] || ICONS.info;
  return /*#__PURE__*/React.createElement("div", {
    role: "status",
    style: {
      display: "flex",
      alignItems: "flex-start",
      gap: 10,
      background: "var(--surface-card)",
      border: "1px solid var(--border-subtle)",
      borderRadius: "var(--radius-nav)",
      boxShadow: "var(--shadow-popover)",
      padding: "12px 14px",
      minWidth: 280,
      maxWidth: 380,
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)",
      ...style
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "18",
    height: "18",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: icon.color,
    strokeWidth: "2.2",
    strokeLinecap: "round",
    strokeLinejoin: "round",
    style: {
      flexShrink: 0,
      marginTop: 1
    }
  }, icon.path), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, title && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-sm)",
      fontWeight: "var(--weight-medium)",
      color: "var(--text-primary)"
    }
  }, title), message && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-sm)",
      color: "var(--text-secondary)",
      marginTop: title ? 2 : 0
    }
  }, message)), onDismiss && /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": "Dismiss",
    onClick: onDismiss,
    style: {
      display: "inline-flex",
      background: "none",
      border: "none",
      padding: 0,
      cursor: "pointer",
      color: "var(--text-tertiary)",
      flexShrink: 0
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "14",
    height: "14",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "2.2",
    strokeLinecap: "round"
  }, /*#__PURE__*/React.createElement("line", {
    x1: "18",
    y1: "6",
    x2: "6",
    y2: "18"
  }), /*#__PURE__*/React.createElement("line", {
    x1: "6",
    y1: "6",
    x2: "18",
    y2: "18"
  }))));
}
Object.assign(__ds_scope, { Toast });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Toast.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Tooltip.jsx
try { (() => {
function Tooltip({
  children,
  label,
  placement = "top",
  style
}) {
  const [show, setShow] = React.useState(false);
  const pos = {
    top: {
      bottom: "calc(100% + 6px)",
      left: "50%",
      transform: "translateX(-50%)"
    },
    bottom: {
      top: "calc(100% + 6px)",
      left: "50%",
      transform: "translateX(-50%)"
    },
    left: {
      right: "calc(100% + 6px)",
      top: "50%",
      transform: "translateY(-50%)"
    },
    right: {
      left: "calc(100% + 6px)",
      top: "50%",
      transform: "translateY(-50%)"
    }
  }[placement];
  return /*#__PURE__*/React.createElement("span", {
    style: {
      position: "relative",
      display: "inline-flex",
      ...style
    },
    onMouseEnter: () => setShow(true),
    onMouseLeave: () => setShow(false),
    onFocus: () => setShow(true),
    onBlur: () => setShow(false)
  }, children, show && /*#__PURE__*/React.createElement("span", {
    role: "tooltip",
    style: {
      position: "absolute",
      ...pos,
      zIndex: 900,
      whiteSpace: "nowrap",
      background: "var(--surface-inverse)",
      color: "var(--text-inverse)",
      fontSize: "var(--text-xs)",
      fontWeight: "var(--weight-medium)",
      letterSpacing: "var(--tracking)",
      padding: "4px 8px",
      borderRadius: 6,
      boxShadow: "var(--shadow-popover)",
      pointerEvents: "none"
    }
  }, label));
}
Object.assign(__ds_scope, { Tooltip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Tooltip.jsx", error: String((e && e.message) || e) }); }

// components/forms/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const SIZES = {
  sm: {
    fontSize: "var(--text-sm)",
    padding: "6px 14px",
    height: 30
  },
  md: {
    fontSize: "var(--text-base)",
    padding: "8px 18px",
    height: 36
  },
  lg: {
    fontSize: "var(--text-base)",
    padding: "11px 22px",
    height: 44
  }
};
const VARIANTS = {
  primary: {
    background: "var(--gray-900)",
    color: "var(--text-inverse)",
    border: "1px solid var(--gray-900)"
  },
  secondary: {
    background: "var(--surface-card)",
    color: "var(--text-primary)",
    border: "1px solid var(--border-default)"
  },
  accent: {
    background: "var(--accent)",
    color: "var(--text-inverse)",
    border: "1px solid var(--accent)"
  },
  ghost: {
    background: "transparent",
    color: "var(--text-primary)",
    border: "1px solid transparent"
  },
  danger: {
    background: "var(--danger)",
    color: "var(--text-inverse)",
    border: "1px solid var(--danger)"
  }
};
function Button({
  children,
  variant = "primary",
  size = "md",
  fullWidth = false,
  disabled = false,
  iconLeft,
  iconRight,
  style,
  ...rest
}) {
  const base = {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    gap: "var(--gap-inline)",
    fontFamily: "var(--font-sans)",
    fontWeight: "var(--weight-medium)",
    letterSpacing: "var(--tracking)",
    borderRadius: "var(--radius-pill)",
    cursor: disabled ? "not-allowed" : "pointer",
    whiteSpace: "nowrap",
    width: fullWidth ? "100%" : "auto",
    transition: "background 120ms ease, border-color 120ms ease, opacity 120ms ease, transform 80ms ease",
    opacity: disabled ? 0.4 : 1,
    userSelect: "none",
    ...SIZES[size],
    ...VARIANTS[variant],
    ...style
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    disabled: disabled,
    style: base,
    onMouseDown: e => {
      if (!disabled) e.currentTarget.style.transform = "scale(0.97)";
    },
    onMouseUp: e => {
      e.currentTarget.style.transform = "scale(1)";
    },
    onMouseLeave: e => {
      e.currentTarget.style.transform = "scale(1)";
    }
  }, rest), iconLeft, children, iconRight);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Button.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Dialog.jsx
try { (() => {
function Dialog({
  open,
  onClose,
  title,
  description,
  children,
  actions,
  width = 440
}) {
  React.useEffect(() => {
    const onKey = e => {
      if (e.key === "Escape") onClose && onClose();
    };
    if (open) window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);
  if (!open) return null;
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClose,
    style: {
      position: "fixed",
      inset: 0,
      background: "rgba(41,41,41,0.32)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      zIndex: 1000,
      padding: 24,
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    role: "dialog",
    "aria-modal": true,
    onClick: e => e.stopPropagation(),
    style: {
      width,
      maxWidth: "100%",
      background: "var(--surface-card)",
      borderRadius: "var(--radius-card)",
      boxShadow: "var(--shadow-modal)",
      padding: 24,
      boxSizing: "border-box"
    }
  }, title && /*#__PURE__*/React.createElement("h2", {
    style: {
      margin: 0,
      fontSize: "var(--text-2xl)",
      fontWeight: "var(--weight-medium)",
      color: "var(--text-primary)",
      letterSpacing: "var(--tracking)"
    }
  }, title), description && /*#__PURE__*/React.createElement("p", {
    style: {
      margin: "8px 0 0",
      fontSize: "var(--text-base)",
      lineHeight: "var(--leading-normal)",
      color: "var(--text-secondary)"
    }
  }, description), children && /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 16
    }
  }, children), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      justifyContent: "flex-end",
      gap: 8,
      marginTop: 24
    }
  }, actions || /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "secondary",
    size: "sm",
    onClick: onClose
  }, "Cancel"), /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "primary",
    size: "sm",
    onClick: onClose
  }, "Confirm")))));
}
Object.assign(__ds_scope, { Dialog });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Dialog.jsx", error: String((e && e.message) || e) }); }

// components/forms/Checkbox.jsx
try { (() => {
function Checkbox({
  label,
  checked,
  defaultChecked,
  disabled = false,
  onChange,
  id,
  style
}) {
  const [internal, setInternal] = React.useState(defaultChecked || false);
  const isControlled = checked !== undefined;
  const on = isControlled ? checked : internal;
  const cbId = id || (label ? `cb-${label.replace(/\s+/g, "-").toLowerCase()}` : undefined);
  const toggle = () => {
    if (disabled) return;
    if (!isControlled) setInternal(v => !v);
    onChange && onChange(!on);
  };
  return /*#__PURE__*/React.createElement("label", {
    htmlFor: cbId,
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 8,
      cursor: disabled ? "not-allowed" : "pointer",
      opacity: disabled ? 0.5 : 1,
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)",
      ...style
    }
  }, /*#__PURE__*/React.createElement("input", {
    id: cbId,
    type: "checkbox",
    checked: on,
    onChange: toggle,
    disabled: disabled,
    style: {
      position: "absolute",
      opacity: 0,
      width: 0,
      height: 0
    }
  }), /*#__PURE__*/React.createElement("span", {
    "aria-hidden": true,
    style: {
      width: 18,
      height: 18,
      borderRadius: 5,
      flexShrink: 0,
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      background: on ? "var(--accent)" : "var(--surface-card)",
      border: `1px solid ${on ? "var(--accent)" : "var(--border-strong)"}`,
      transition: "background 120ms ease, border-color 120ms ease"
    }
  }, on && /*#__PURE__*/React.createElement("svg", {
    width: "12",
    height: "12",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "#fff",
    strokeWidth: "3",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("polyline", {
    points: "20 6 9 17 4 12"
  }))), label && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--text-base)",
      color: "var(--text-primary)"
    }
  }, label));
}
Object.assign(__ds_scope, { Checkbox });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Checkbox.jsx", error: String((e && e.message) || e) }); }

// components/forms/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
function IconButton({
  children,
  size = "md",
  variant = "ghost",
  disabled = false,
  "aria-label": ariaLabel,
  style,
  ...rest
}) {
  const dims = {
    sm: 28,
    md: 32,
    lg: 36
  }[size];
  const variants = {
    ghost: {
      background: "transparent",
      color: "var(--text-secondary)",
      border: "1px solid transparent"
    },
    outline: {
      background: "var(--surface-card)",
      color: "var(--text-primary)",
      border: "1px solid var(--border-default)"
    },
    soft: {
      background: "var(--surface-sunken)",
      color: "var(--text-primary)",
      border: "1px solid transparent"
    }
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    disabled: disabled,
    "aria-label": ariaLabel,
    style: {
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      width: dims,
      height: dims,
      borderRadius: "var(--radius-nav)",
      cursor: disabled ? "not-allowed" : "pointer",
      opacity: disabled ? 0.4 : 1,
      transition: "background 120ms ease, color 120ms ease",
      ...variants[variant],
      ...style
    },
    onMouseEnter: e => {
      if (!disabled && variant === "ghost") e.currentTarget.style.background = "var(--surface-hover)";
    },
    onMouseLeave: e => {
      if (variant === "ghost") e.currentTarget.style.background = "transparent";
    }
  }, rest), children);
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/forms/Input.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
function Input({
  label,
  hint,
  error,
  size = "md",
  leadingIcon,
  trailingIcon,
  disabled = false,
  id,
  style,
  ...rest
}) {
  const inputId = id || (label ? `in-${label.replace(/\s+/g, "-").toLowerCase()}` : undefined);
  const height = {
    sm: 30,
    md: 36,
    lg: 44
  }[size];
  const fontSize = size === "sm" ? "var(--text-sm)" : "var(--text-base)";
  const borderColor = error ? "var(--danger)" : "var(--border-default)";
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 6,
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)"
    }
  }, label && /*#__PURE__*/React.createElement("label", {
    htmlFor: inputId,
    style: {
      fontSize: "var(--text-sm)",
      fontWeight: "var(--weight-medium)",
      color: "var(--text-primary)"
    }
  }, label), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      display: "flex",
      alignItems: "center"
    }
  }, leadingIcon && /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      left: 10,
      display: "inline-flex",
      color: "var(--text-tertiary)",
      pointerEvents: "none"
    }
  }, leadingIcon), /*#__PURE__*/React.createElement("input", _extends({
    id: inputId,
    disabled: disabled,
    style: {
      width: "100%",
      height,
      boxSizing: "border-box",
      padding: `0 ${trailingIcon ? 34 : 12}px 0 ${leadingIcon ? 32 : 12}px`,
      fontSize,
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)",
      color: "var(--text-primary)",
      background: disabled ? "var(--surface-sunken)" : "var(--surface-card)",
      border: `1px solid ${borderColor}`,
      borderRadius: "var(--radius-nav)",
      outline: "none",
      transition: "border-color 120ms ease, box-shadow 120ms ease",
      ...style
    },
    onFocus: e => {
      if (!error) {
        e.target.style.borderColor = "var(--border-focus)";
        e.target.style.boxShadow = "var(--ring)";
      }
    },
    onBlur: e => {
      e.target.style.borderColor = borderColor;
      e.target.style.boxShadow = "none";
    }
  }, rest)), trailingIcon && /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      right: 10,
      display: "inline-flex",
      color: "var(--text-tertiary)"
    }
  }, trailingIcon)), (hint || error) && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--text-xs)",
      color: error ? "var(--danger)" : "var(--text-tertiary)"
    }
  }, error || hint));
}
Object.assign(__ds_scope, { Input });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Input.jsx", error: String((e && e.message) || e) }); }

// components/forms/Radio.jsx
try { (() => {
function Radio({
  label,
  checked,
  disabled = false,
  onChange,
  name,
  value,
  style
}) {
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 8,
      cursor: disabled ? "not-allowed" : "pointer",
      opacity: disabled ? 0.5 : 1,
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)",
      ...style
    }
  }, /*#__PURE__*/React.createElement("input", {
    type: "radio",
    name: name,
    value: value,
    checked: checked,
    disabled: disabled,
    onChange: () => onChange && onChange(value),
    style: {
      position: "absolute",
      opacity: 0,
      width: 0,
      height: 0
    }
  }), /*#__PURE__*/React.createElement("span", {
    "aria-hidden": true,
    style: {
      width: 18,
      height: 18,
      borderRadius: "var(--radius-pill)",
      flexShrink: 0,
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      background: "var(--surface-card)",
      border: `1px solid ${checked ? "var(--accent)" : "var(--border-strong)"}`,
      transition: "border-color 120ms ease"
    }
  }, checked && /*#__PURE__*/React.createElement("span", {
    style: {
      width: 8,
      height: 8,
      borderRadius: "var(--radius-pill)",
      background: "var(--accent)"
    }
  })), label && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--text-base)",
      color: "var(--text-primary)"
    }
  }, label));
}
Object.assign(__ds_scope, { Radio });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Radio.jsx", error: String((e && e.message) || e) }); }

// components/forms/Select.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
function Select({
  label,
  hint,
  options = [],
  size = "md",
  disabled = false,
  id,
  style,
  ...rest
}) {
  const selId = id || (label ? `sel-${label.replace(/\s+/g, "-").toLowerCase()}` : undefined);
  const height = {
    sm: 30,
    md: 36,
    lg: 44
  }[size];
  const fontSize = size === "sm" ? "var(--text-sm)" : "var(--text-base)";
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 6,
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)"
    }
  }, label && /*#__PURE__*/React.createElement("label", {
    htmlFor: selId,
    style: {
      fontSize: "var(--text-sm)",
      fontWeight: "var(--weight-medium)",
      color: "var(--text-primary)"
    }
  }, label), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      display: "flex",
      alignItems: "center"
    }
  }, /*#__PURE__*/React.createElement("select", _extends({
    id: selId,
    disabled: disabled,
    style: {
      width: "100%",
      height,
      boxSizing: "border-box",
      padding: "0 32px 0 12px",
      fontSize,
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)",
      color: "var(--text-primary)",
      background: disabled ? "var(--surface-sunken)" : "var(--surface-card)",
      border: "1px solid var(--border-default)",
      borderRadius: "var(--radius-nav)",
      appearance: "none",
      outline: "none",
      cursor: disabled ? "not-allowed" : "pointer",
      transition: "border-color 120ms ease, box-shadow 120ms ease",
      ...style
    },
    onFocus: e => {
      e.target.style.borderColor = "var(--border-focus)";
      e.target.style.boxShadow = "var(--ring)";
    },
    onBlur: e => {
      e.target.style.borderColor = "var(--border-default)";
      e.target.style.boxShadow = "none";
    }
  }, rest), options.map(o => {
    const value = typeof o === "string" ? o : o.value;
    const text = typeof o === "string" ? o : o.label;
    return /*#__PURE__*/React.createElement("option", {
      key: value,
      value: value
    }, text);
  })), /*#__PURE__*/React.createElement("svg", {
    width: "14",
    height: "14",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "var(--text-tertiary)",
    strokeWidth: "2",
    strokeLinecap: "round",
    strokeLinejoin: "round",
    style: {
      position: "absolute",
      right: 10,
      pointerEvents: "none"
    }
  }, /*#__PURE__*/React.createElement("polyline", {
    points: "6 9 12 15 18 9"
  }))), hint && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--text-xs)",
      color: "var(--text-tertiary)"
    }
  }, hint));
}
Object.assign(__ds_scope, { Select });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Select.jsx", error: String((e && e.message) || e) }); }

// components/forms/Switch.jsx
try { (() => {
function Switch({
  checked,
  defaultChecked,
  disabled = false,
  onChange,
  label,
  id,
  style
}) {
  const [internal, setInternal] = React.useState(defaultChecked || false);
  const isControlled = checked !== undefined;
  const on = isControlled ? checked : internal;
  const toggle = () => {
    if (disabled) return;
    if (!isControlled) setInternal(v => !v);
    onChange && onChange(!on);
  };
  const track = /*#__PURE__*/React.createElement("span", {
    role: "switch",
    "aria-checked": on,
    "aria-label": label,
    tabIndex: disabled ? -1 : 0,
    onClick: toggle,
    onKeyDown: e => {
      if (e.key === " " || e.key === "Enter") {
        e.preventDefault();
        toggle();
      }
    },
    style: {
      width: 40,
      height: 24,
      borderRadius: "var(--radius-pill)",
      flexShrink: 0,
      background: on ? "var(--accent)" : "var(--gray-300)",
      position: "relative",
      cursor: disabled ? "not-allowed" : "pointer",
      transition: "background 160ms ease",
      display: "inline-block"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      top: 2,
      left: on ? 18 : 2,
      width: 20,
      height: 20,
      borderRadius: "var(--radius-pill)",
      background: "#fff",
      boxShadow: "0 1px 3px rgba(41,41,41,0.25)",
      transition: "left 160ms ease"
    }
  }));
  if (!label) return /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: disabled ? 0.5 : 1,
      ...style
    }
  }, track);
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 10,
      opacity: disabled ? 0.5 : 1,
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)",
      ...style
    }
  }, track, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--text-base)",
      color: "var(--text-primary)"
    }
  }, label));
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Switch.jsx", error: String((e && e.message) || e) }); }

// components/icon/Icon.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Icon — Material Symbols (Outlined) wrapper.
   Host pages must load the font:
   <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200">
   `name` is a Material Symbols identifier (snake_case, e.g. "chat_bubble").
   14px for navigation, 20px for cards. */
function Icon({
  name,
  size = 20,
  color = "currentColor",
  fill = false,
  weight = 400,
  style,
  ...rest
}) {
  const opsz = Math.min(48, Math.max(20, size));
  return /*#__PURE__*/React.createElement("span", _extends({
    "aria-hidden": "true",
    style: {
      fontFamily: '"Material Symbols Outlined"',
      fontWeight: "normal",
      fontStyle: "normal",
      fontSize: size,
      lineHeight: 1,
      letterSpacing: "normal",
      textTransform: "none",
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      whiteSpace: "nowrap",
      wordWrap: "normal",
      direction: "ltr",
      color,
      userSelect: "none",
      WebkitFontSmoothing: "antialiased",
      fontVariationSettings: `'FILL' ${fill ? 1 : 0}, 'wght' ${weight}, 'GRAD' 0, 'opsz' ${opsz}`,
      ...style
    }
  }, rest), name);
}
Object.assign(__ds_scope, { Icon });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/icon/Icon.jsx", error: String((e && e.message) || e) }); }

// components/navigation/Tabs.jsx
try { (() => {
function Tabs({
  tabs = [],
  value,
  defaultValue,
  onChange,
  style
}) {
  const items = tabs.map(t => typeof t === "string" ? {
    value: t,
    label: t
  } : t);
  const [internal, setInternal] = React.useState(defaultValue || items[0] && items[0].value);
  const active = value !== undefined ? value : internal;
  const select = v => {
    if (value === undefined) setInternal(v);
    onChange && onChange(v);
  };
  const pillRef = React.useRef(null);
  const btnRefs = React.useRef({});
  const firstPaint = React.useRef(true);
  const EASE = "cubic-bezier(0.22, 1, 0.36, 1)";
  const DUR = "220ms";
  const positionPill = React.useCallback(animate => {
    const pill = pillRef.current;
    const btn = btnRefs.current[active];
    if (!pill || !btn) return;
    if (!animate) pill.style.transition = "none";
    pill.style.transform = `translateX(${btn.offsetLeft}px)`;
    pill.style.width = `${btn.offsetWidth}px`;
    pill.style.height = `${btn.offsetHeight}px`;
    if (!animate) {
      void pill.offsetWidth;
      pill.style.transition = `transform ${DUR} ${EASE}, width ${DUR} ${EASE}`;
    }
  }, [active]);
  React.useLayoutEffect(() => {
    positionPill(!firstPaint.current);
    firstPaint.current = false;
  }, [active, positionPill, items.length]);
  React.useEffect(() => {
    const onResize = () => positionPill(false);
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, [positionPill]);
  return /*#__PURE__*/React.createElement("div", {
    role: "tablist",
    style: {
      position: "relative",
      display: "inline-flex",
      alignItems: "center",
      gap: "var(--gap-nav)",
      background: "var(--surface-sunken)",
      padding: 3,
      borderRadius: "var(--radius-nav)",
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)",
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    ref: pillRef,
    style: {
      position: "absolute",
      top: 3,
      left: 0,
      height: 28,
      width: 0,
      background: "var(--surface-card)",
      borderRadius: 6,
      boxShadow: "var(--shadow-card)",
      transform: "translateX(0)",
      transition: `transform ${DUR} ${EASE}, width ${DUR} ${EASE}`,
      willChange: "transform, width",
      zIndex: 0,
      pointerEvents: "none"
    }
  }), items.map(t => {
    const on = t.value === active;
    return /*#__PURE__*/React.createElement("button", {
      key: t.value,
      role: "tab",
      "aria-selected": on,
      ref: el => {
        btnRefs.current[t.value] = el;
      },
      onClick: () => select(t.value),
      style: {
        position: "relative",
        zIndex: 1,
        border: "none",
        cursor: "pointer",
        fontSize: "var(--text-sm)",
        fontWeight: "var(--weight-medium)",
        letterSpacing: "var(--tracking)",
        padding: "6px 12px",
        borderRadius: 6,
        background: "transparent",
        color: on ? "var(--text-primary)" : "var(--text-secondary)",
        transition: `color ${DUR} ${EASE}`
      }
    }, t.label);
  }));
}
Object.assign(__ds_scope, { Tabs });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/Tabs.jsx", error: String((e && e.message) || e) }); }

// ui_kits/workspace/App.jsx
try { (() => {
/* Fidelio Workspace — app shell tying screens together */
const {
  Toast,
  Dialog,
  Input,
  Button
} = window.ApplkeDesignSystem_795038;
function KitApp() {
  const [route, setRoute] = React.useState("projects");
  const [dialog, setDialog] = React.useState(false);
  const [toast, setToast] = React.useState(false);
  const titles = {
    home: "Home",
    projects: "Projects",
    tasks: "Tasks",
    calendar: "Calendar",
    messages: "Messages",
    settings: "Settings",
    help: "Help"
  };
  const createProject = () => {
    setDialog(false);
    setToast(true);
    setTimeout(() => setToast(false), 3200);
  };
  let view;
  if (route === "settings") view = /*#__PURE__*/React.createElement(KitSettings, null);else if (route === "projects") view = /*#__PURE__*/React.createElement(KitProjects, null);else view = /*#__PURE__*/React.createElement(EmptyState, {
    label: titles[route]
  });
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      height: "100vh",
      background: "var(--surface-page)",
      fontFamily: "var(--font-sans)",
      letterSpacing: "var(--tracking)"
    }
  }, /*#__PURE__*/React.createElement(KitSidebar, {
    active: route,
    onNavigate: setRoute
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "flex",
      flexDirection: "column",
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement(KitTopbar, {
    title: titles[route],
    onNew: () => setDialog(true)
  }), /*#__PURE__*/React.createElement("main", {
    style: {
      flex: 1,
      overflow: "auto",
      background: "var(--surface-sunken)"
    }
  }, view)), /*#__PURE__*/React.createElement(Dialog, {
    open: dialog,
    onClose: () => setDialog(false),
    title: "New project",
    description: "Give your project a name to get started.",
    actions: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "sm",
      onClick: () => setDialog(false)
    }, "Cancel"), /*#__PURE__*/React.createElement(Button, {
      variant: "primary",
      size: "sm",
      onClick: createProject
    }, "Create"))
  }, /*#__PURE__*/React.createElement(Input, {
    label: "Project name",
    placeholder: "e.g. Website redesign",
    autoFocus: true
  })), toast && /*#__PURE__*/React.createElement("div", {
    style: {
      position: "fixed",
      bottom: 20,
      right: 20,
      zIndex: 1100
    }
  }, /*#__PURE__*/React.createElement(Toast, {
    tone: "success",
    title: "Project created",
    message: "Your new project is ready.",
    onDismiss: () => setToast(false)
  })));
}
function EmptyState({
  label
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: "100%",
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      justifyContent: "center",
      gap: 8,
      color: "var(--text-tertiary)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-2xl)",
      fontWeight: 500,
      color: "var(--text-secondary)"
    }
  }, label), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-sm)"
    }
  }, "This screen is a placeholder in the kit."));
}
Object.assign(window, {
  KitApp
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/workspace/App.jsx", error: String((e && e.message) || e) }); }

// ui_kits/workspace/ProjectsView.jsx
try { (() => {
/* Fidelio Workspace — Projects view */
const {
  Icon,
  Card,
  Badge,
  Tag,
  Tabs,
  Button
} = window.ApplkeDesignSystem_795038;
const PROJECTS = [{
  name: "Marketing site",
  icon: "dashboard",
  tone: "success",
  status: "Active",
  meta: "Edited 2h ago",
  tags: ["design", "web"],
  progress: 72,
  members: ["JD", "AL", "RM"]
}, {
  name: "Mobile app v2",
  icon: "smartphone",
  tone: "accent",
  status: "In review",
  meta: "Edited yesterday",
  tags: ["product"],
  progress: 44,
  members: ["AL", "KP"]
}, {
  name: "Q3 campaign",
  icon: "campaign",
  tone: "warning",
  status: "Planning",
  meta: "Edited 3d ago",
  tags: ["growth", "content"],
  progress: 18,
  members: ["RM"]
}, {
  name: "Design system",
  icon: "widgets",
  tone: "success",
  status: "Active",
  meta: "Edited 5h ago",
  tags: ["design"],
  progress: 90,
  members: ["JD", "KP", "AL", "RM"]
}, {
  name: "API platform",
  icon: "dns",
  tone: "neutral",
  status: "Paused",
  meta: "Edited 1w ago",
  tags: ["eng"],
  progress: 55,
  members: ["KP"]
}, {
  name: "Onboarding flow",
  icon: "route",
  tone: "accent",
  status: "In review",
  meta: "Edited 4h ago",
  tags: ["product", "ux"],
  progress: 63,
  members: ["JD", "AL"]
}];
function Avatar({
  id,
  i
}) {
  const colors = [["#D7E4FD", "#1A4CB8"], ["#E9F6EE", "#248049"], ["#FBF2E1", "#A66A07"], ["#FCECEC", "#BE2E2E"]];
  const [bg, fg] = colors[i % colors.length];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width: 24,
      height: 24,
      borderRadius: "var(--radius-pill)",
      background: bg,
      color: fg,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 11,
      fontWeight: 500,
      marginLeft: i ? -6 : 0,
      border: "2px solid var(--surface-card)"
    }
  }, id);
}
function ProjectCard({
  p
}) {
  return /*#__PURE__*/React.createElement(Card, {
    interactive: true
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "flex-start",
      justifyContent: "space-between"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 36,
      height: 36,
      borderRadius: "var(--radius-nav)",
      background: "var(--surface-sunken)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center"
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: p.icon,
    size: 20,
    color: "var(--text-secondary)"
  })), /*#__PURE__*/React.createElement(Badge, {
    tone: p.tone,
    dot: p.status === "Active"
  }, p.status)), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-base)",
      fontWeight: 500,
      color: "var(--text-primary)",
      marginTop: 14,
      letterSpacing: "var(--tracking)"
    }
  }, p.name), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-xs)",
      color: "var(--text-tertiary)",
      marginTop: 2
    }
  }, p.meta), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      height: 5,
      borderRadius: "var(--radius-pill)",
      background: "var(--surface-sunken)",
      overflow: "hidden"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: p.progress + "%",
      height: "100%",
      background: "var(--accent)"
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-xs)",
      color: "var(--text-tertiary)",
      marginTop: 6
    }
  }, p.progress, "% complete")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      marginTop: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 6
    }
  }, p.tags.map(t => /*#__PURE__*/React.createElement(Tag, {
    key: t
  }, t))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex"
    }
  }, p.members.map((m, i) => /*#__PURE__*/React.createElement(Avatar, {
    key: m + i,
    id: m,
    i: i
  })))));
}
function KitProjects() {
  const [tab, setTab] = React.useState("All");
  return /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 20
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      marginBottom: 18
    }
  }, /*#__PURE__*/React.createElement(Tabs, {
    tabs: ["All", "Active", "In review", "Archived"],
    value: tab,
    onChange: setTab
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(Button, {
    size: "sm",
    variant: "secondary",
    iconLeft: /*#__PURE__*/React.createElement(Icon, {
      name: "tune",
      size: 14
    })
  }, "Filter"), /*#__PURE__*/React.createElement(Button, {
    size: "sm",
    variant: "ghost",
    iconLeft: /*#__PURE__*/React.createElement(Icon, {
      name: "swap_vert",
      size: 14
    })
  }, "Sort"))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "grid",
      gridTemplateColumns: "repeat(auto-fill, minmax(268px, 1fr))",
      gap: 16
    }
  }, PROJECTS.map(p => /*#__PURE__*/React.createElement(ProjectCard, {
    key: p.name,
    p: p
  }))));
}
Object.assign(window, {
  KitProjects
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/workspace/ProjectsView.jsx", error: String((e && e.message) || e) }); }

// ui_kits/workspace/SettingsView.jsx
try { (() => {
/* Fidelio Workspace — Settings view */
const {
  Card,
  Input,
  Select,
  Switch,
  Checkbox,
  Button,
  Badge
} = window.ApplkeDesignSystem_795038;
function Row({
  title,
  desc,
  children,
  last
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      gap: 24,
      padding: "16px 0",
      borderBottom: last ? "none" : "1px solid var(--border-subtle)"
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-base)",
      fontWeight: 500,
      color: "var(--text-primary)",
      letterSpacing: "var(--tracking)"
    }
  }, title), desc && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-sm)",
      color: "var(--text-secondary)",
      marginTop: 2,
      maxWidth: 380,
      lineHeight: 1.5
    }
  }, desc)), /*#__PURE__*/React.createElement("div", {
    style: {
      flexShrink: 0
    }
  }, children));
}
function SectionTitle({
  children
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-xs)",
      fontWeight: 500,
      color: "var(--text-tertiary)",
      textTransform: "uppercase",
      letterSpacing: "0.4px",
      margin: "4px 0 8px"
    }
  }, children);
}
function KitSettings() {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 20,
      maxWidth: 720
    }
  }, /*#__PURE__*/React.createElement(SectionTitle, null, "Profile"), /*#__PURE__*/React.createElement(Card, {
    style: {
      marginBottom: 24
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 16,
      alignItems: "flex-end"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement(Input, {
    label: "Full name",
    defaultValue: "Jordan Diaz"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement(Input, {
    label: "Email",
    defaultValue: "jordan@fidelio.com"
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 16,
      marginTop: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement(Select, {
    label: "Timezone",
    options: ["Pacific (PT)", "Mountain (MT)", "Central (CT)", "Eastern (ET)"]
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement(Select, {
    label: "Language",
    options: ["English", "Español", "Français", "Deutsch"]
  })))), /*#__PURE__*/React.createElement(SectionTitle, null, "Notifications"), /*#__PURE__*/React.createElement(Card, {
    style: {
      marginBottom: 24,
      padding: "0 16px"
    }
  }, /*#__PURE__*/React.createElement(Row, {
    title: "Product updates",
    desc: "News about features and improvements."
  }, /*#__PURE__*/React.createElement(Switch, {
    defaultChecked: true
  })), /*#__PURE__*/React.createElement(Row, {
    title: "Mentions",
    desc: "When someone @mentions you in a comment."
  }, /*#__PURE__*/React.createElement(Switch, {
    defaultChecked: true
  })), /*#__PURE__*/React.createElement(Row, {
    title: "Weekly digest",
    desc: "A Monday summary of activity across your projects.",
    last: true
  }, /*#__PURE__*/React.createElement(Switch, null))), /*#__PURE__*/React.createElement(SectionTitle, null, "Danger zone"), /*#__PURE__*/React.createElement(Card, {
    style: {
      borderColor: "var(--red-100, #F3CFCF)"
    }
  }, /*#__PURE__*/React.createElement(Row, {
    title: "Delete workspace",
    desc: "Permanently remove this workspace and all of its projects.",
    last: true
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "danger",
    size: "sm"
  }, "Delete"))));
}
Object.assign(window, {
  KitSettings
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/workspace/SettingsView.jsx", error: String((e && e.message) || e) }); }

// ui_kits/workspace/Sidebar.jsx
try { (() => {
/* Fidelio Workspace — left navigation rail */
const {
  Icon,
  Badge
} = window.ApplkeDesignSystem_795038;
function KitSidebar({
  active,
  onNavigate
}) {
  const nav = [{
    key: "home",
    label: "Home",
    icon: "home"
  }, {
    key: "projects",
    label: "Projects",
    icon: "folder",
    badge: "12"
  }, {
    key: "tasks",
    label: "Tasks",
    icon: "check_box"
  }, {
    key: "calendar_month",
    label: "Calendar",
    icon: "calendar_month"
  }, {
    key: "messages",
    label: "Messages",
    icon: "chat_bubble",
    badge: "3"
  }];
  const bottom = [{
    key: "settings",
    label: "Settings",
    icon: "settings"
  }, {
    key: "help",
    label: "Help",
    icon: "support"
  }];
  const NavItem = ({
    item
  }) => {
    const on = active === item.key;
    return /*#__PURE__*/React.createElement("button", {
      onClick: () => onNavigate(item.key),
      style: {
        display: "flex",
        alignItems: "center",
        gap: 10,
        width: "100%",
        padding: "8px 10px",
        border: "none",
        cursor: "pointer",
        textAlign: "left",
        background: on ? "var(--surface-active)" : "transparent",
        color: on ? "var(--text-primary)" : "var(--text-secondary)",
        borderRadius: "var(--radius-nav)",
        fontSize: "var(--text-sm)",
        fontWeight: on ? 500 : 400,
        fontFamily: "var(--font-sans)",
        letterSpacing: "var(--tracking)",
        transition: "background 120ms ease"
      },
      onMouseEnter: e => {
        if (!on) e.currentTarget.style.background = "var(--surface-hover)";
      },
      onMouseLeave: e => {
        if (!on) e.currentTarget.style.background = "transparent";
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: item.icon,
      size: 14,
      color: on ? "var(--text-primary)" : "var(--text-tertiary)"
    }), /*#__PURE__*/React.createElement("span", {
      style: {
        flex: 1
      }
    }, item.label), item.badge && /*#__PURE__*/React.createElement(Badge, {
      tone: on ? "accent" : "neutral"
    }, item.badge));
  };
  return /*#__PURE__*/React.createElement("aside", {
    style: {
      width: 232,
      flexShrink: 0,
      background: "var(--surface-page)",
      borderRight: "1px solid var(--border-subtle)",
      display: "flex",
      flexDirection: "column",
      padding: 12,
      boxSizing: "border-box",
      height: "100%"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8,
      padding: "6px 10px 14px"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 24,
      height: 24,
      borderRadius: 6,
      background: "var(--gray-900)",
      color: "#fff",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 13,
      fontWeight: 500
    }
  }, "F"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--text-base)",
      fontWeight: 500,
      color: "var(--text-primary)",
      letterSpacing: "var(--tracking)"
    }
  }, "Fidelio"), /*#__PURE__*/React.createElement(Icon, {
    name: "unfold_more",
    size: 14,
    color: "var(--text-tertiary)",
    style: {
      marginLeft: "auto"
    }
  })), /*#__PURE__*/React.createElement("nav", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: "var(--gap-nav)"
    }
  }, nav.map(i => /*#__PURE__*/React.createElement(NavItem, {
    key: i.key,
    item: i
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: "auto",
      display: "flex",
      flexDirection: "column",
      gap: "var(--gap-nav)"
    }
  }, bottom.map(i => /*#__PURE__*/React.createElement(NavItem, {
    key: i.key,
    item: i
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 10,
      padding: "8px 10px",
      marginTop: 4,
      borderTop: "1px solid var(--border-subtle)",
      paddingTop: 12
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 26,
      height: 26,
      borderRadius: "var(--radius-pill)",
      background: "var(--blue-100)",
      color: "var(--blue-700)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 12,
      fontWeight: 500
    }
  }, "JD"), /*#__PURE__*/React.createElement("div", {
    style: {
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-sm)",
      fontWeight: 500,
      color: "var(--text-primary)",
      letterSpacing: "var(--tracking)"
    }
  }, "Jordan Diaz"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-xs)",
      color: "var(--text-tertiary)"
    }
  }, "jordan@fidelio.com")))));
}
Object.assign(window, {
  KitSidebar
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/workspace/Sidebar.jsx", error: String((e && e.message) || e) }); }

// ui_kits/workspace/Topbar.jsx
try { (() => {
/* Fidelio Workspace — top bar with title, search, actions */
const {
  Icon,
  IconButton,
  Button,
  Input,
  Tooltip
} = window.ApplkeDesignSystem_795038;
function KitTopbar({
  title,
  onNew
}) {
  return /*#__PURE__*/React.createElement("header", {
    style: {
      height: 56,
      flexShrink: 0,
      display: "flex",
      alignItems: "center",
      gap: 12,
      padding: "0 20px",
      borderBottom: "1px solid var(--border-subtle)",
      background: "var(--surface-page)"
    }
  }, /*#__PURE__*/React.createElement("h1", {
    style: {
      margin: 0,
      fontSize: "var(--text-2xl)",
      fontWeight: 500,
      color: "var(--text-primary)",
      letterSpacing: "var(--tracking)"
    }
  }, title), /*#__PURE__*/React.createElement("div", {
    style: {
      marginLeft: "auto",
      width: 240
    }
  }, /*#__PURE__*/React.createElement(Input, {
    size: "sm",
    placeholder: "Search",
    leadingIcon: /*#__PURE__*/React.createElement(Icon, {
      name: "search",
      size: 14
    })
  })), /*#__PURE__*/React.createElement(Tooltip, {
    label: "Notifications"
  }, /*#__PURE__*/React.createElement(IconButton, {
    "aria-label": "Notifications"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "notifications",
    size: 14
  }))), /*#__PURE__*/React.createElement(Button, {
    size: "sm",
    variant: "primary",
    iconLeft: /*#__PURE__*/React.createElement(Icon, {
      name: "add",
      size: 14
    }),
    onClick: onNew
  }, "New project"));
}
Object.assign(window, {
  KitTopbar
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/workspace/Topbar.jsx", error: String((e && e.message) || e) }); }

// ui_kits/workspace/doc-page.js
try { (() => {
// @ds-adherence-ignore -- omelette starter scaffold (raw elements/hex/px by design)
// Copied omelette starter. Re-running copy_starter_component with this kind overwrites this file with the latest version (page content is unaffected).
/* BEGIN USAGE */
/**
 * <doc-page> — paged-document shell for printable HTML.
 *
 * FIRST, decide how the document paginates — up front, before building:
 *
 * - FLOWING document (the default): write the whole document as one
 *   normal HTML flow inside <doc-page>; the browser's print engine
 *   splits it onto pages at export. Use for long-form documents with a
 *   single text flow: reports, memos, letters, essays.
 * - EXPLICIT pagination: a fixed set of pre-paginated pages, one
 *   <section class="page"> child per page. Use when the user asks for a
 *   specific page count, or the design implies one: a one-page resume, a
 *   two-sided flier, a poster, a certificate, a brochure — any richly
 *   laid-out document without a single text flow.
 * - If in doubt, ask the user as part of the build.
 *
 * PAGE SIZING — paper differs by country (letter vs A4), so the printed
 * sheet is not one fixed truth:
 * - FLOWING documents pin NO paper size: the print engine paginates
 *   onto the user's real paper, and the content reflows to it.
 * - EXPLICITLY PAGINATED documents print each page at a FIXED page box
 *   with overflow hidden — letter by default, size="a4" for a clearly
 *   metric user, the user's chosen paper when they export. Design each
 *   page to FILL that box, fitting letter and A4 alike without overlap.
 * - width/height pin an explicit fixed size, ONLY when the user gives
 *   one.
 * Never write your own @page rule or hard-code paper dimensions in the
 * content.
 *
 * Sizing modes (attributes):
 *   (none)                      — portrait: flowing docs use the user's
 *           paper; explicitly paginated pages use the named size box
 *           (letter unless size="a4")
 *   orientation="landscape"     — the same, landscape
 *   width / height              — explicit fixed size, ONLY when the user
 *           gives one (e.g. width="22in" height="30in" for a 22×30
 *           poster): the page IS the design's size, printed at true
 *           dimensions (or scaled onto the user's paper at print time).
 *           Any absolute CSS length: px/in/mm/cm/pt/pc.
 * The component announces the chosen mode to the host app at runtime (a
 * meta tag it injects), so the print path can inject the user's true
 * paper size.
 *
 * On screen the document renders on a desk background: a flowing
 * document as one tall scrolling sheet (Google Docs' pageless view);
 * explicitly paginated documents as one card per page.
 *
 * EXPLICIT pagination usage:
 *   <style>doc-page:not(:defined){visibility:hidden}</style>
 *   <doc-page>
 *     <section class="page" id="p1">…one page's design…</section>
 *     <section class="page" id="p2">…</section>
 *   </doc-page>
 *   <script src="doc-page.js"></script>
 * How the page box works, concretely: each .page prints as ONE full-bleed
 * sheet at a FIXED physical size — letter by default (set size="a4" for
 * a clearly metric user), the user's chosen paper when they export —
 * with overflow hidden. Nothing scrolls and nothing reflows onto a next
 * sheet: content that misses the box is CLIPPED. Design each page to
 * FILL that page box, and to fit it — letter and A4 alike — without
 * overlap. Each page is a size container; don't size anything in
 * viewport units (they track the window, not the page), and never set
 * width or height on the .page section itself (the component sizes the
 * page box; an authored height like 100% is meaningless at print and is
 * overridden). The component owns the page box, the screen card chrome,
 * and the page breaks (never add your own break-before/after). Don't mix
 * .page sections with flowing content or header/footer slots in the same
 * document.
 *
 * FLOWING usage:
 *   <style>doc-page:not(:defined){visibility:hidden}</style>
 *   <doc-page margin="0.75in">
 *     <h1>Title</h1>
 *     <p>…body…</p>
 *   </doc-page>
 *   <script src="doc-page.js"></script>
 * There is no manual page-splitting — the browser's print engine
 * paginates at export. Standard break-hygiene rules (`break-inside:
 * avoid` on figures, code blocks, images and table rows; `orphans/
 * widows: 3`) are applied so paragraphs and groups split cleanly. On
 * screen and at print, headings default to `text-wrap: balance` and
 * body text to `text-wrap: pretty`; the defaults have zero specificity,
 * so any text-wrap you declare wins.
 *
 * Other attributes:
 *   size    — letter | a4 | legal (default letter). Flowing documents:
 *           preview proportion only — it does NOT pin their printed
 *           paper (the print dialog's paper governs); leave it alone
 *           there. Explicitly paginated documents: it sets the page box
 *           the cards and the pinned @page share (the export dialog's
 *           choice overrides both at print) — set size="a4" for a
 *           clearly metric user. Scaled-fit: names the sheet the fit is
 *           computed against, same a4-for-metric-users advice.
 *   content-width / content-height — the design's own fixed dimensions
 *           (CSS lengths), for scaling a fixed-size design ONTO the
 *           named sheet: content lays out at exactly this size, and the
 *           component scales it to fit that sheet's printable area
 *           (centered horizontally, top-aligned; the export dialog
 *           re-fits to the user's actual paper choice where available).
 *           Both must be set; they do not change the page box. For pages
 *           WITHOUT running header/footer slots.
 *   margin  — printable inset on every page of a FLOWING document
 *           (default 0.75in); margin="0" makes pages full-bleed.
 *           Explicitly paginated pages are always full-bleed.
 *
 * Running header/footer (flowing documents only): give an element
 * `slot="header"` or `slot="footer"` and it repeats on every printed
 * page via `position: fixed`. To keep body text from sliding under it,
 * the component prints inside a single-cell table whose <thead>/<tfoot>
 * are spacers sized to the header/footer height — browsers repeat
 * thead/tfoot on every page, so each sheet's content starts below the
 * header and ends above the footer. On screen the header/footer render
 * once at the top/bottom of the sheet.
 *
 * At print the component injects `@page { margin: 0 }` (which leaves
 * Chrome no margin box to draw its date/URL/page-count header in) and
 * moves the visual margin onto the sheet's own padding. It also marks
 * the document as owning its print CSS (a
 * `meta[name="omelette-owns-print"]` it injects at runtime), so the
 * PDF export never injects page-geometry CSS of its own on top.
 *
 * Print best practices for the content you author:
 * - Multi-column text: use CSS columns (`column-count` +
 *   `column-gap`), never side-by-side flex/grid columns — only real
 *   CSS columns flow and break across pages. `column-span: all` lets
 *   a heading span the columns; `hyphens: auto` (needs `lang` on
 *   the html element) keeps narrow columns readable.
 * - Page breaks in flowing documents: `break-before: page` on an
 *   element that must start a new page (a chapter, an appendix). Add
 *   your own kept-together blocks (callouts, stat tiles, cards) to a
 *   `break-inside: avoid` rule, and keep each one shorter than a page.
 * - Extend `orphans: 3; widows: 3` to any custom text blocks you add
 *   (p and li are covered by default).
 * - Give long tables a <thead> — browsers repeat it on every printed
 *   page.
 * - No `position: fixed`/`sticky` and no viewport units in content:
 *   fixed elements stamp every printed page (running headers/footers go
 *   in the component's slots) and `100vh` mis-sizes at print.
 *
 * Author content as static HTML so the user can click-to-edit any text
 * directly. Do not set width/padding/background on the document body —
 * the component owns the sheet box.
 */
/* END USAGE */

(() => {
  const PAPER = {
    letter: ['8.5in', '11in'],
    a4: ['210mm', '297mm'],
    legal: ['8.5in', '14in']
  };
  const CSS_LENGTH = /^\d+(\.\d+)?(px|in|mm|cm|pt|pc)$/;
  // Unitless "0" is a valid CSS length and the natural way to write
  // margin="0"; normalise it to 0px so max()/calc() (which reject a bare
  // number) keep working.
  const safeLen = (v, fb) => {
    v = (v || '').trim();
    return v === '0' ? '0px' : CSS_LENGTH.test(v) ? v : fb;
  };
  // WebKit (Safari and every iOS browser shell) never repeats a table's
  // thead/tfoot on printed pages (WebKit bug 17205), so the spacer-borne
  // vertical margins of a FLOWING document reach only the first page
  // there. Engine check, not browser check: vendor is 'Apple Computer,
  // Inc.' exactly for WebKit and 'Google Inc.' for Blink.
  const WK_PRINT = /apple/i.test(navigator.vendor || '');
  // CSS length → px number (CSS absolute units are exact: 1in = 96px).
  // Returns NaN for anything safeLen would reject — callers gate on it.
  const PX_PER = {
    px: 1,
    in: 96,
    mm: 96 / 25.4,
    cm: 96 / 2.54,
    pt: 96 / 72,
    pc: 16
  };
  const toPx = v => {
    const m = /^(\d+(?:\.\d+)?)(px|in|mm|cm|pt|pc)$/.exec((v || '').trim());
    return m ? parseFloat(m[1]) * PX_PER[m[2]] : NaN;
  };
  const stylesheet = `
    :host {
      position: relative;
      display: block;
      /* When the viewport is narrower than the page, grow to wrap the
       * sheet (plus this padding) instead of staying viewport-width, so
       * the desk background and right margin reach the sheet's far edge
       * in the horizontal scroll. */
      min-width: max-content;
      min-height: 100vh;
      background: #f5f5f4;
      padding: 48px 24px;
      box-sizing: border-box;
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
      --doc-page-w: 8.5in;
      --doc-page-h: 11in;
      --doc-page-margin: 0.75in;
      --doc-hdr-h: 0px;
      --doc-ftr-h: 0px;
      --doc-hdr-pad: 0px;
      --doc-ftr-pad: 0px;
    }
    .sheet {
      width: var(--doc-page-w);
      margin: 0 auto;
      background: #fff;
      box-shadow: 0 2px 10px rgba(20, 20, 19, 0.12);
      border-radius: 7px;
      box-sizing: border-box;
      padding: var(--doc-page-margin);
    }
    .frame { width: 100%; border-collapse: collapse; }
    /* Scaled-fit mode (content-width/content-height): the inner .fit box
     * lays the content out at its authored fixed size and scales it onto
     * the printable area; .fit-box reserves the scaled footprint in flow
     * (transforms don't affect layout) and centers it. Without the mode,
     * both divs are unstyled block pass-throughs. */
    /* Explicit pagination: direct .page children are the pages. The sheet
     * becomes a transparent stack and each page carries the card look on
     * screen; at print each page is exactly one full-bleed sheet. The
     * ::slotted defaults are deliberately weak (document CSS wins), so
     * authored page styling can override any of this. */
    .sheet.paginated {
      background: transparent;
      box-shadow: none;
      border-radius: 0;
      padding: 0;
    }
    .paginated ::slotted(.page) {
      position: relative;
      display: block;
      width: 100%;
      aspect-ratio: var(--doc-page-ar);
      container-type: size;
      overflow: hidden;
      box-sizing: border-box;
      background: #fff;
      border-radius: 7px;
      box-shadow: 0 2px 10px rgba(0, 0, 0, 0.25);
      print-color-adjust: exact;
      -webkit-print-color-adjust: exact;
      break-inside: avoid;
    }
    .paginated ::slotted(.page:not(:first-child)) { margin-top: 1rem; }
    @media print {
      .sheet.paginated { padding: 0; }
      /* The flowing-document vertical inset lives on the repeating
       * thead/tfoot spacers, not the sheet padding — they must go too,
       * or each full-sheet .page is pushed ~margin down and spills onto
       * a second sheet. Paginated pages are full-bleed by definition
       * (content owns its insets). */
      .sheet.paginated .hdr-space,
      .sheet.paginated .ftr-space { height: 0; }
      .paginated ::slotted(.page) {
        border-radius: 0 !important;
        box-shadow: none !important;
        margin: 0 !important;
        /* Physical page-box sizing, no viewport units: Safari resolves
         * 100vh against the window, not the page box, so a vh-sized card
         * paginates wrong there. --doc-page-w/h are the named size by
         * default and are overridden to the user's chosen paper by the
         * export path, so every card is exactly one sheet either way.
         * Width + height (same source values as @page size) rather than
         * width + aspect-ratio: the ratio is a 6-decimal rounding of the
         * same division, and a few millionths of overflow would spill a
         * blank sheet after every page. The screen-only aspect-ratio
         * (preview proportions) must not leak into print. cqh typography
         * tracks the same box.
         *
         * Every declaration is !important: per CSS Scoping, unimportant
         * shadow ::slotted rules LOSE to the document context, so a page
         * section's authored inline style would silently beat this print
         * geometry. A model-authored height:100% did exactly that — the
         * percentage resolves as auto in the all-auto print ancestry, the
         * base rule's size containment turns auto into ZERO, and
         * overflow:hidden then paints nothing: a blank PDF with perfect
         * page boxes. At print the component's geometry is the design's
         * whole contract, so it must win over any authored sizing. */
        aspect-ratio: auto !important;
        width: var(--doc-page-w) !important;
        height: var(--doc-page-h) !important;
        overflow: hidden !important;
      }
      .paginated ::slotted(.page:not(:first-child)) {
        break-before: page !important;
        margin-top: 0 !important;
      }
    }
    .fit-mode .fit-box {
      width: calc(var(--doc-fit-w) * var(--doc-fit-scale));
      height: calc(var(--doc-fit-h) * var(--doc-fit-scale));
      margin: 0 auto;
      break-inside: avoid;
    }
    .fit-mode .fit {
      width: var(--doc-fit-w);
      height: var(--doc-fit-h);
      transform: scale(var(--doc-fit-scale));
      transform-origin: top left;
    }
    .frame td, .frame th { padding: 0; text-align: left; font-weight: inherit; }
    .hdr-space { height: var(--doc-hdr-h); }
    .ftr-space { height: var(--doc-ftr-h); }
    ::slotted([slot="header"]),
    ::slotted([slot="footer"]) { display: block; box-sizing: border-box; }
    @media print {
      :host { background: none; padding: 0; min-width: 0; min-height: 0; }
      .sheet {
        width: auto; margin: 0; box-shadow: none; border-radius: 0;
        padding: 0 var(--doc-page-margin);
      }
      /* The thead/tfoot spacers repeat on every page, so they carry the
       * vertical page margin (which the sheet's own padding cannot, since
       * that padding is consumed once on the first/last page). The running
       * header/footer are fixed inside that band. */
      /* The 0.35in is breathing room between a running header/footer and
       * the body; without one the spacer is exactly the page margin, so a
       * margin="0" full-bleed document gets truly full-bleed pages. */
      .hdr-space { height: max(var(--doc-page-margin), calc(var(--doc-hdr-h) + var(--doc-hdr-pad))); }
      .ftr-space { height: max(var(--doc-page-margin), calc(var(--doc-ftr-h) + var(--doc-ftr-pad))); }
      /* WebKit flowing documents: @page carries the vertical margin (see
       * _syncPrintPageRule), so the spacers keep only whatever a running
       * header/footer needs BEYOND it — page 1 would otherwise double its
       * top inset. Paginated sheets already zero their spacers above. */
      .sheet.wk-print:not(.paginated) .hdr-space { height: max(0px, calc(max(var(--doc-page-margin), calc(var(--doc-hdr-h) + var(--doc-hdr-pad))) - var(--doc-page-margin))); }
      .sheet.wk-print:not(.paginated) .ftr-space { height: max(0px, calc(max(var(--doc-page-margin), calc(var(--doc-ftr-h) + var(--doc-ftr-pad))) - var(--doc-page-margin))); }
      ::slotted([slot="header"]) {
        position: fixed; top: 0; left: 0; right: 0; margin: 0;
        padding: calc(var(--doc-page-margin) * 0.45) var(--doc-page-margin) 0;
      }
      ::slotted([slot="footer"]) {
        position: fixed; bottom: 0; left: 0; right: 0; margin: 0;
        padding: 0 var(--doc-page-margin) calc(var(--doc-page-margin) * 0.45);
      }
    }
  `;
  class DocPage extends HTMLElement {
    static get observedAttributes() {
      return ['size', 'width', 'height', 'margin', 'orientation', 'content-width', 'content-height'];
    }
    constructor() {
      super();
      this._root = this.attachShadow({
        mode: 'open'
      });
      this._mo = typeof MutationObserver === 'function' ? new MutationObserver(() => this._scheduleMeasure()) : null;
    }

    /** The named paper's [w, h], swapped when orientation="landscape".
     *  Only the named size swaps — explicit width/height are exact values
     *  the author already oriented. */
    _paperSize() {
      const named = PAPER[(this.getAttribute('size') || '').toLowerCase()] || PAPER.letter;
      const landscape = (this.getAttribute('orientation') || '').trim().toLowerCase() === 'landscape';
      return landscape ? [named[1], named[0]] : named;
    }
    get pageWidth() {
      return safeLen(this.getAttribute('width'), this._paperSize()[0]);
    }
    get pageHeight() {
      return safeLen(this.getAttribute('height'), this._paperSize()[1]);
    }
    get pageMargin() {
      return safeLen(this.getAttribute('margin'), '0.75in');
    }

    /** Scaled-fit mode's content box [w, h] as CSS lengths, or null when
     *  the mode is off (either attribute missing/invalid/zero — a partial
     *  declaration falls back to normal flow rather than guessing). */
    _contentFit() {
      const w = safeLen(this.getAttribute('content-width'), null);
      const h = safeLen(this.getAttribute('content-height'), null);
      if (!w || !h) return null;
      const wPx = toPx(w),
        hPx = toPx(h);
      return wPx > 0 && hPx > 0 ? [w, h, wPx, hPx] : null;
    }
    connectedCallback() {
      if (!this._sheet) this._render();
      this._syncSize();
      this._syncPrintPageRule();
      this._ensureTextWrapDefaults();
      this._ensureOwnsPrintMeta();
      this._syncFixedSizeMeta();
      this._syncPrintSizingMeta();
      if (this._mo) this._mo.observe(this, {
        subtree: true,
        childList: true,
        characterData: true,
        attributes: true
      });
      this._onResize = () => this._scheduleMeasure();
      window.addEventListener('resize', this._onResize);
      if (document.fonts && document.fonts.ready) {
        document.fonts.ready.then(() => this._scheduleMeasure());
      }
      this._scheduleMeasure();
    }
    disconnectedCallback() {
      window.removeEventListener('resize', this._onResize);
      if (this._mo) this._mo.disconnect();
      if (this._raf) {
        cancelAnimationFrame(this._raf);
        this._raf = null;
      }
      // Drop the head rules when the last doc-page leaves, so a deleted
      // document's @page geometry and text-wrap defaults can't apply to
      // whatever replaces it.
      const survivor = document.querySelector('doc-page');
      if (!survivor) {
        ['doc-page-print', 'doc-page-text-wrap', 'doc-page-owns-print', 'doc-page-fixed-size', 'doc-page-print-sizing'].forEach(id => {
          const tag = document.getElementById(id);
          if (tag) tag.remove();
        });
        // A live deck-stage deferred its own print-sizing meta to ours —
        // hand the page-global meta over so the deck isn't left unmarked.
        const deck = document.querySelector('deck-stage');
        if (deck && typeof deck._ensurePrintSizingMeta === 'function') {
          deck._ensurePrintSizingMeta();
        }
      } else {
        // A departed owner hands each page-global meta to whatever
        // doc-page remains (or it's removed).
        if (typeof survivor._syncFixedSizeMeta === 'function') {
          survivor._syncFixedSizeMeta();
        }
        if (typeof survivor._syncPrintSizingMeta === 'function') {
          survivor._syncPrintSizingMeta();
        }
      }
    }
    attributeChangedCallback() {
      if (!this._sheet) return;
      this._syncSize();
      this._syncPrintPageRule();
      this._syncFixedSizeMeta();
      this._syncPrintSizingMeta();
      this._scheduleMeasure();
    }
    _render() {
      this._root.innerHTML = `
        <style>${stylesheet}</style>
        <style id="vars"></style>
        <div class="sheet" data-screen-label="Document">
          <table class="frame" role="presentation">
            <thead><tr><th><div class="hdr-space"><slot name="header"></slot></div></th></tr></thead>
            <tbody><tr><td class="body"><div class="fit-box"><div class="fit"><slot></slot></div></div></td></tr></tbody>
            <tfoot><tr><td><div class="ftr-space"><slot name="footer"></slot></div></td></tr></tfoot>
          </table>
        </div>`;
      this._sheet = this._root.querySelector('.sheet');
      this._vars = this._root.getElementById('vars');
    }

    /** Runtime sizing lives in a shadow <style> :host rule, never on the
     *  light-DOM host element, so serialize-persist can't write it back. */
    _syncSize(hdrH, ftrH) {
      // Scaled-fit mode: content at its authored size, scaled onto the
      // printable area (page minus margins on both axes). The factor is a
      // plain number var so calc(length * number) stays valid; 4 decimals
      // keeps the shadow style stable across re-measures. Upscaling is
      // allowed — print transforms are vector, so text and CSS stay crisp
      // (raster images soften, which the catalog bullet warns about).
      const fit = this._contentFit();
      let fitVars = '';
      if (fit) {
        const marginPx = toPx(this.pageMargin) || 0;
        const availW = toPx(this.pageWidth) - 2 * marginPx;
        const availH = toPx(this.pageHeight) - 2 * marginPx;
        const scale = Math.min(availW / fit[2], availH / fit[3]);
        if (scale > 0 && Number.isFinite(scale)) {
          fitVars = '--doc-fit-w:' + fit[0] + ';' + '--doc-fit-h:' + fit[1] + ';' + '--doc-fit-scale:' + scale.toFixed(4) + ';';
        }
      }
      this._sheet.classList.toggle('fit-mode', !!fitVars);
      // Numeric w/h ratio for the paginated page cards' aspect-ratio —
      // aspect-ratio takes a number, not a length ratio, so compute it
      // here (CSS length division isn't portable). 6 decimals keeps the
      // shadow style stable across re-syncs.
      const arW = toPx(this.pageWidth);
      const arH = toPx(this.pageHeight);
      const ar = arW > 0 && arH > 0 ? (arW / arH).toFixed(6) : '0.772727';
      this._vars.textContent = ':host{' + fitVars + '--doc-page-ar:' + ar + ';' + '--doc-page-w:' + this.pageWidth + ';' + '--doc-page-h:' + this.pageHeight + ';' + '--doc-page-margin:' + this.pageMargin + ';' + '--doc-hdr-h:' + (hdrH || 0) + 'px;' + '--doc-ftr-h:' + (ftrH || 0) + 'px;' + '--doc-hdr-pad:' + (hdrH ? '0.35in' : '0px') + ';' + '--doc-ftr-pad:' + (ftrH ? '0.35in' : '0px') + '}';
    }

    /** @page is a no-op inside shadow DOM, so the rule lives in <head>.
     *  Re-appended on every sync so it stays last in source order — the
     *  @page cascade is source-order per descriptor, so this rule wins
     *  over any other @page rule in the document.
     *
     *  The @page SIZE is pinned where the page box IS part of the design:
     *  explicit-fixed-size mode (width + height authored), scaled-fit
     *  mode (the named sheet the fit targets), and explicit pagination
     *  (the named size the cards share — so card and sheet agree on
     *  every print path, and the export path's chosen paper overrides
     *  BOTH with one later rule). For FLOWING documents no paper size is
     *  emitted at all — the true size comes from the user's preference,
     *  injected by the export path or chosen in the print dialog — so a
     *  flowing document never fights the paper it lands on.
     *  margin: 0 is emitted in every mode: it leaves Chrome no margin box
     *  to draw its date/URL/page-count header in, and the visual margin
     *  lives on the sheet's own padding. */
    _syncPrintPageRule() {
      const id = 'doc-page-print';
      let tag = document.getElementById(id);
      if (!tag) {
        tag = document.createElement('style');
        tag.id = id;
      }
      document.head.appendChild(tag);
      // Three print-geometry regimes:
      // - true-size: the page IS the design — pin its exact size.
      // - scaled-fit (content-width/height): the fit factor is computed
      //   against the NAMED paper's printable area, so that paper must
      //   stay pinned or the scaled content overflows a smaller sheet
      //   (the export path re-fits and re-pins at print time on top).
      // - default modes: no paper size — but landscape still needs the
      //   paper-agnostic 'size: landscape' keyword, because the size
      //   descriptor is what carries orientation; without it a landscape
      //   document prints portrait whenever nothing injects a size.
      const landscape = (this.getAttribute('orientation') || '').trim().toLowerCase() === 'landscape';
      // Explicit pagination pins the page box to the SAME values that
      // size the cards (the named size by default, the export path's
      // chosen paper when its later rule overrides both) — card and
      // sheet agree on every print path, and a mismatched real paper
      // shrinks-to-fit in the dialog instead of clipping a Letter card
      // on A4. Declared before the paginated read below so both derive
      // from one check.
      const paginatedNow = this.querySelector(':scope > .page') !== null;
      const sizeDescriptor = this._trueSizePx() ? 'size: ' + this.pageWidth + ' ' + this.pageHeight + '; ' : this._contentFit() ? 'size: ' + this.pageWidth + ' ' + this.pageHeight + '; ' : paginatedNow ? 'size: ' + this.pageWidth + ' ' + this.pageHeight + '; ' : landscape ? 'size: landscape; ' : '';
      // WebKit never repeats the thead/tfoot spacers that carry a flowing
      // document's vertical page margins (see WK_PRINT above), so pages
      // after the first print edge-to-edge there. Carry the VERTICAL
      // margins on @page for WebKit instead, and the shadow print CSS
      // trims the first-page spacers by the same amount (.sheet.wk-print
      // rules). Horizontal inset stays on the sheet's own padding in
      // every engine. Blink keeps margin: 0 (a nonzero margin there
      // re-opens the box Chrome draws its header furniture in). One cost,
      // learned in testing: Safari's own date/URL headers are a USER
      // dialog setting ("Print headers and footers") that renders in the
      // margin area when room exists — margin: 0 only suppressed it by
      // leaving no room, and no CSS controls it. The export dialog's
      // Safari guide teaches turning the setting off for flowing
      // documents. Explicitly paginated and fixed-size documents keep
      // margin: 0 everywhere: their pages ARE the sheet.
      const wkFlowing = WK_PRINT && !paginatedNow && !this._trueSizePx() && !this._contentFit();
      const marginDescriptor = wkFlowing ? 'margin: ' + this.pageMargin + ' 0; ' : 'margin: 0; ';
      // Shadow-internal marker (never serialized), kept in lockstep with
      // the @page decision above: the print CSS trims the first-page
      // spacers ONLY while @page actually carries the margins — a
      // true-size or scaled-fit sheet keeps margin: 0 and must keep its
      // spacers too. Re-synced here so attribute changes and pagination
      // flips move both together.
      if (this._sheet) this._sheet.classList.toggle('wk-print', wkFlowing);
      tag.textContent = '@page { ' + sizeDescriptor + marginDescriptor + '} ' + '@media print { html, body { margin: 0 !important; padding: 0 !important; background: none !important; height: auto !important; overflow: visible !important; } ' + 'h1,h2,h3,h4,h5,h6 { break-after: avoid; } ' + 'figure,pre,blockquote,img,svg,tr { break-inside: avoid; } ' + 'p,li { orphans: 3; widows: 3; } ' + '* { -webkit-print-color-adjust: exact; print-color-adjust: exact; ' + 'backdrop-filter: none !important; -webkit-backdrop-filter: none !important; } ' + '*, *::before, *::after { animation-delay: -99s !important; animation-duration: .001s !important; ' + 'animation-iteration-count: 1 !important; animation-fill-mode: both !important; ' + 'animation-play-state: running !important; transition-duration: 0s !important; } }';
    }

    /** Typographic defaults for document text: balance headings, avoid
     *  widowed/orphaned words in body copy (browsers without text-wrap
     *  support drop the declarations). Zero-specificity via :where() so
     *  any text-wrap authored on those elements wins; document-level so the
     *  rules reach the slotted (light DOM) content — shadow styles can't.
     *  data-omelette-injected marks the tag for the host editor to strip
     *  at serialize, so it is never written back as authored source. */
    _ensureTextWrapDefaults() {
      if (document.getElementById('doc-page-text-wrap')) return;
      const tag = document.createElement('style');
      tag.id = 'doc-page-text-wrap';
      tag.setAttribute('data-omelette-injected', '');
      tag.textContent = ':where(h1,h2,h3,h4,h5,h6){text-wrap:balance}' + ':where(p,li,blockquote,figcaption){text-wrap:pretty}';
      document.head.appendChild(tag);
    }

    /** Declares that this document owns its print CSS. The instant-PDF
     *  export checks for the meta by NAME PRESENCE alone (content is
     *  ignored) and skips its automatic print-CSS injections, so the
     *  component's @page geometry is never overridden by a heuristic.
     *  data-omelette-injected keeps it out of serialized source. */
    _ensureOwnsPrintMeta() {
      if (document.getElementById('doc-page-owns-print')) return;
      const tag = document.createElement('meta');
      tag.id = 'doc-page-owns-print';
      tag.name = 'omelette-owns-print';
      tag.content = 'true';
      tag.setAttribute('data-omelette-injected', '');
      document.head.appendChild(tag);
    }

    /** This page's valid true-size page box (explicit width AND height)
     *  as [w, h] px ints, or null when the mode is off. */
    _trueSizePx() {
      if (!safeLen(this.getAttribute('width'), null) || !safeLen(this.getAttribute('height'), null)) return null;
      const w = Math.round(toPx(this.pageWidth));
      const h = Math.round(toPx(this.pageHeight));
      return w > 0 && h > 0 ? [w, h] : null;
    }

    /** True-size pages (explicit width AND height) also declare the page
     *  box as the preview size: the in-app preview reads
     *  meta[name="omelette-fixed-size"] (content "W,H" in px ints) and
     *  scales the sheet into view — without it an 18in poster previews at
     *  true size with scrollbars. Never overrides an author-set meta
     *  (only the component's own id is managed). The meta is page-global
     *  while doc-page instances are not, so every sync recomputes the
     *  page-wide owner — the first connected true-size doc-page — and a
     *  non-true-size sibling's sync can never delete the owner's meta.
     *  Removed when no true-size page remains (the owner's disconnect
     *  re-syncs via any survivor) or when an author-set meta exists. */
    _syncFixedSizeMeta() {
      const id = 'doc-page-fixed-size';
      const own = document.getElementById(id);
      const authored = document.querySelector('meta[name="omelette-fixed-size"]:not([data-omelette-injected])');
      // The page-wide owner, not this instance: an upgraded true-size page
      // anywhere in the document keeps the meta alive and sized.
      let box = null;
      for (const el of document.querySelectorAll('doc-page')) {
        box = typeof el._trueSizePx === 'function' ? el._trueSizePx() : null;
        if (box) break;
      }
      if (!box || authored) {
        if (own) own.remove();
        return;
      }
      const tag = own || document.createElement('meta');
      tag.id = id;
      tag.name = 'omelette-fixed-size';
      tag.content = box[0] + ',' + box[1];
      tag.setAttribute('data-omelette-injected', '');
      if (!own) document.head.appendChild(tag);
    }

    /** This page's print-sizing mode: 'fixed' when an explicit width AND
     *  height are authored (the page is the design's own size), else the
     *  default paper in the authored orientation. */
    _printSizingMode() {
      if (this._trueSizePx()) return 'fixed';
      const landscape = (this.getAttribute('orientation') || '').trim().toLowerCase() === 'landscape';
      return landscape ? 'default-landscape' : 'default-portrait';
    }

    /** Announces the print-sizing mode to the host app:
     *  meta[name="omelette-print-sizing"] with content 'default-portrait',
     *  'default-landscape', or 'fixed' (fixed pages also carry the
     *  omelette-fixed-size meta with the page box in px). The export path
     *  probes it to decide what true paper size to inject at print time —
     *  in the default modes the component emits no paper size of its own.
     *  Same page-global ownership rules as the fixed-size meta above:
     *  first connected doc-page owns it, an authored meta is never
     *  overridden, removed when no doc-page remains. */
    _syncPrintSizingMeta() {
      const id = 'doc-page-print-sizing';
      const own = document.getElementById(id);
      const authored = document.querySelector('meta[name="omelette-print-sizing"]:not([data-omelette-injected])');
      // A fixed page wins outright (mirroring the fixed-size loop above,
      // so the two metas can never contradict each other in a mixed
      // multi-page document); otherwise the first page's mode holds.
      let mode = null;
      for (const el of document.querySelectorAll('doc-page')) {
        if (typeof el._printSizingMode !== 'function') continue;
        const m = el._printSizingMode();
        if (m === 'fixed') {
          mode = m;
          break;
        }
        if (mode === null) mode = m;
      }
      if (!mode || authored) {
        if (own) own.remove();
        return;
      }
      // A deck-stage that connected first injected its own meta and
      // defers to any existing one — take it over, or the document ends
      // up with two conflicting injected metas (a doc-page page is the
      // document; the deck re-ensures its meta if every doc-page leaves).
      const deckMeta = document.getElementById('deck-stage-print-sizing');
      if (deckMeta) deckMeta.remove();
      const tag = own || document.createElement('meta');
      tag.id = id;
      tag.name = 'omelette-print-sizing';
      tag.content = mode;
      tag.setAttribute('data-omelette-injected', '');
      if (!own) document.head.appendChild(tag);
    }
    _scheduleMeasure() {
      if (this._raf) return;
      this._raf = requestAnimationFrame(() => {
        this._raf = null;
        this._measure();
      });
    }

    /** Slot heights feed the print spacers (--doc-hdr-h / --doc-ftr-h), so
     *  they re-measure on content mutation, resize, and font load. The
     *  same pass detects explicit pagination (direct .page children) and
     *  toggles the sheet between the flowing-document card and the
     *  page-per-card stack — content edits can add or remove pages at any
     *  time, so this tracks the same mutations the measurement does. */
    _measure() {
      const hdr = this.querySelector(':scope > [slot="header"]');
      const ftr = this.querySelector(':scope > [slot="footer"]');
      const wasPaginated = this._sheet.classList.contains('paginated');
      this._sheet.classList.toggle('paginated', this.querySelector(':scope > .page') !== null);
      // The WebKit @page margin is flowing-only, so a pagination flip
      // must re-emit the rule (content edits can add or remove .page
      // sections at any time).
      if (this._sheet.classList.contains('paginated') !== wasPaginated) {
        this._syncPrintPageRule();
      }
      this._syncSize(hdr ? hdr.offsetHeight : 0, ftr ? ftr.offsetHeight : 0);
    }
  }
  if (!customElements.get('doc-page')) {
    customElements.define('doc-page', DocPage);
  }
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/workspace/doc-page.js", error: String((e && e.message) || e) }); }

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.Tag = __ds_scope.Tag;

__ds_ns.Dialog = __ds_scope.Dialog;

__ds_ns.Toast = __ds_scope.Toast;

__ds_ns.Tooltip = __ds_scope.Tooltip;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Checkbox = __ds_scope.Checkbox;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.Radio = __ds_scope.Radio;

__ds_ns.Select = __ds_scope.Select;

__ds_ns.Switch = __ds_scope.Switch;

__ds_ns.Icon = __ds_scope.Icon;

__ds_ns.Tabs = __ds_scope.Tabs;

})();
