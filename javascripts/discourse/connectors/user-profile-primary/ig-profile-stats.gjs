import IgProfileStats from "../../components/ig-profile-stats";

const IgProfileStatsConnector = <template>
  <IgProfileStats @user={{@outletArgs.model}} />
</template>;

export default IgProfileStatsConnector;
