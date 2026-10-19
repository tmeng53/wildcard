import { nameText, typedText } from '@wildcard/typed-text';

/** The optional line under a 练了 or a meal: trimmed, 1 to 60 characters, one line. */
export const Caption = typedText({
  max: 60,
  oneLine: true,
  description: 'Trimmed, then 1 to 60 characters as people see them, on one line.',
});

/** A 今日免责声明: trimmed, 1 to 80 characters, and it may span lines. */
export const DisclaimerText = typedText({
  max: 80,
  oneLine: false,
  description: 'Trimmed, then 1 to 80 characters as people see them; may span lines.',
});

/** 其他: a sport the member names: trimmed, 1 to 20 characters, one line with plain spaces. */
export const CustomSportName = nameText({
  max: 20,
  description: 'Trimmed, then 1 to 20 characters as people see them, on one line.',
});
