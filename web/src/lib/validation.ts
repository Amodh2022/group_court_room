/** Mirrors the server's limits so the user gets feedback before a round trip.
 *  The server remains the authority; this is purely a nicer failure mode. */

export const LIMITS = {
  nickname: { min: 1, max: 40 },
  defense: { min: 10, max: 1000 },
  title: { min: 3, max: 80 },
  accusation: { min: 10, max: 1000 },
} as const;

export interface DefenseErrors {
  nickname?: string;
  body?: string;
}

export function validateDefense(nickname: string, body: string): DefenseErrors {
  const errors: DefenseErrors = {};
  const name = nickname.trim();
  const text = body.trim();

  if (name.length < LIMITS.nickname.min) {
    errors.nickname = "The court needs a name to address you by.";
  } else if (name.length > LIMITS.nickname.max) {
    errors.nickname = `Keep it under ${LIMITS.nickname.max} characters.`;
  }

  if (text.length === 0) {
    errors.body = "You have to say something in your defense.";
  } else if (text.length < LIMITS.defense.min) {
    errors.body = `That is too short to be a defense — at least ${LIMITS.defense.min} characters.`;
  } else if (text.length > LIMITS.defense.max) {
    errors.body = `Brevity is a virtue. Keep it under ${LIMITS.defense.max} characters.`;
  }

  return errors;
}

export interface CaseErrors {
  title?: string;
  accusation?: string;
  defendant?: string;
}

export function validateCase(
  title: string,
  accusation: string,
  defendant: string,
): CaseErrors {
  const errors: CaseErrors = {};
  const name = title.trim();
  const charge = accusation.trim();
  const accused = defendant.trim();

  if (name.length < LIMITS.title.min) {
    errors.title = `Every case needs a name — at least ${LIMITS.title.min} characters.`;
  } else if (name.length > LIMITS.title.max) {
    errors.title = `Keep the title under ${LIMITS.title.max} characters.`;
  }

  if (charge.length < LIMITS.accusation.min) {
    errors.accusation = `Tell the court what actually happened — at least ${LIMITS.accusation.min} characters.`;
  } else if (charge.length > LIMITS.accusation.max) {
    errors.accusation = `The court has other cases. Keep it under ${LIMITS.accusation.max} characters.`;
  }

  if (accused.length > LIMITS.nickname.max) {
    errors.defendant = `Keep the name under ${LIMITS.nickname.max} characters.`;
  }

  return errors;
}

export const hasErrors = (errors: object): boolean => Object.keys(errors).length > 0;
