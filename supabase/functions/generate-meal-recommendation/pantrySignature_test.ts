import { assertEquals, assertNotEquals } from "jsr:@std/assert";
import { computePantrySignature, pantryToIngredientsDescription } from "./pantrySignature.ts";

Deno.test("computePantrySignature: order-independent -- add/remove order never changes the signature", () => {
  const a = [{ name: "Rice", quantity: 2, unit: "cups" }, { name: "chicken breast", quantity: null, unit: null }];
  const b = [{ name: "chicken breast", quantity: null, unit: null }, { name: "Rice", quantity: 2, unit: "cups" }];
  assertEquals(computePantrySignature(a), computePantrySignature(b));
});

Deno.test("computePantrySignature: case-insensitive on name", () => {
  const a = [{ name: "Onion", quantity: null, unit: null }];
  const b = [{ name: "onion", quantity: null, unit: null }];
  assertEquals(computePantrySignature(a), computePantrySignature(b));
});

Deno.test("computePantrySignature: a real edit (quantity change) changes the signature -- this is what triggers regeneration", () => {
  const before = [{ name: "rice", quantity: 2, unit: "cups" }];
  const after = [{ name: "rice", quantity: 3, unit: "cups" }];
  assertNotEquals(computePantrySignature(before), computePantrySignature(after));
});

Deno.test("computePantrySignature: adding/removing an item changes the signature", () => {
  const before = [{ name: "rice", quantity: null, unit: null }];
  const after = [{ name: "rice", quantity: null, unit: null }, { name: "onion", quantity: null, unit: null }];
  assertNotEquals(computePantrySignature(before), computePantrySignature(after));
});

Deno.test("computePantrySignature: empty pantry is stable and distinct from any non-empty one", () => {
  assertEquals(computePantrySignature([]), computePantrySignature([]));
  assertNotEquals(computePantrySignature([]), computePantrySignature([{ name: "salt", quantity: null, unit: null }]));
});

Deno.test("pantryToIngredientsDescription: joins name-only items plainly", () => {
  const items = [{ name: "onion", quantity: null, unit: null }, { name: "salt", quantity: null, unit: null }];
  assertEquals(pantryToIngredientsDescription(items), "onion, salt");
});

Deno.test("pantryToIngredientsDescription: prefixes quantity+unit when present", () => {
  const items = [{ name: "rice", quantity: 2, unit: "cups" }, { name: "chicken breast", quantity: null, unit: null }];
  assertEquals(pantryToIngredientsDescription(items), "2 cups rice, chicken breast");
});

Deno.test("pantryToIngredientsDescription: quantity with no unit still reads naturally", () => {
  const items = [{ name: "eggs", quantity: 6, unit: null }];
  assertEquals(pantryToIngredientsDescription(items), "6 eggs");
});
