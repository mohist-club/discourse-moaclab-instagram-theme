import { apiInitializer } from "discourse/lib/api";
import IgMessagesDock from "../components/ig-messages-dock";

// Instagram's floating Messages dock. Rendered as a component in an outlet
// outside #main-outlet-wrapper so it never becomes a grid item; whether it
// shows (setting, login, desktop, route) is decided at render time.
export default apiInitializer((api) => {
  api.renderInOutlet("below-footer", IgMessagesDock);
});
