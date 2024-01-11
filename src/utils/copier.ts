/**
 *
 * @param source the object whose properties need to be copied
 * @param keys the propeties name array to copy
 * @returns object with selected properites
 */
export function copy<T, K extends keyof T>(source: T, keys: K[]): Pick<T, K> {
  return keys.reduce(
    (acc, key) => ({ ...acc, [key]: source[key] }),
    {} as Pick<T, K>,
  );
}
