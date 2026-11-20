import IgStudioHeader from "../../components/ig-studio-header";

const IgStudioHeaderConnector = <template>
  <IgStudioHeader @category={{@outletArgs.category}} />
</template>;

export default IgStudioHeaderConnector;
