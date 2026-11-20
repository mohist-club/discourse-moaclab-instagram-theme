import IgProfileGrid from "../../components/ig-profile-grid";

const IgProfileGridConnector = <template>
  <IgProfileGrid @user={{@outletArgs.user}} />
</template>;

export default IgProfileGridConnector;
