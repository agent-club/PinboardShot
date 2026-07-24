import type { Metadata } from "next";
import { PinboardShotHome } from "../page";
import { localizedMetadata } from "../seo";

export const metadata: Metadata = localizedMetadata("zh");

export default function ChinesePage() {
  return <PinboardShotHome initialLanguage="zh" lockInitialLanguage />;
}
