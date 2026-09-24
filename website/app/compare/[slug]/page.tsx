import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ContentPage } from "@/app/_components/content-page";
import { contentPageMetadata } from "@/app/seo";
import { contentPageParams, getContentPage } from "@/content/content-pages";

type PageProps = { params: Promise<{ slug: string }> };

export const dynamicParams = false;

export function generateStaticParams() {
  return contentPageParams("compare");
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { slug } = await params;
  const page = getContentPage("compare", slug);
  return page ? contentPageMetadata(page) : {};
}

export default async function ComparisonPage({ params }: PageProps) {
  const { slug } = await params;
  const page = getContentPage("compare", slug);
  if (!page) notFound();
  return <ContentPage page={page} />;
}
