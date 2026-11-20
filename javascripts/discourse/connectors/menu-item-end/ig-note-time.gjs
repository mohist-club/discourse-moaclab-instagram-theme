import formatDate from "discourse/helpers/format-date";

// Instagram shows when each activity happened. Discourse's notification
// rows have no time, so this adds one; it is only shown on the phone
// notifications page (scss/mobile-notifications.scss).
const IgNoteTime = <template>
  {{#if @outletArgs.notification.created_at}}
    <span class="ig-note-time">{{formatDate
        @outletArgs.notification.created_at
        format="tiny"
        noTitle="true"
      }}</span>
  {{/if}}
</template>;

export default IgNoteTime;
