import Category from "discourse/models/category";
import { studioParentIds } from "../components/ig-studio-header";

// The studios page (instagram_studios_page): Discourse's own subcategories
// page of the first studio parent (instagram_suggested_categories, e.g.
// /c/keyboards/13/subcategories). Shared by the rail link
// (ig-navigation.js) and the page itself (components/ig-studios-page.gjs).

export function studiosParentId() {
  return settings.instagram_studios_page ? studioParentIds()[0] || 0 : 0;
}

// null when the setting is off or the parent category is not visible
export function studiosPath() {
  const id = studiosParentId();
  const url = id && Category.findById(id)?.url;
  return url ? `${url}/subcategories` : null;
}

export function isStudiosPath(pathname = window.location.pathname) {
  const path = studiosPath();
  return !!path && pathname.replace(/\/$/, "") === path;
}
