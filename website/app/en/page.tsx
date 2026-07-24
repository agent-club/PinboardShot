import type { Metadata } from "next";
import { PinboardShotHome } from "../page";
import { localizedMetadata } from "../seo";

export const metadata: Metadata = localizedMetadata("en");

export default function EnglishPage() {
  return <PinboardShotHome initialLanguage="en" lockInitialLanguage />;
}
