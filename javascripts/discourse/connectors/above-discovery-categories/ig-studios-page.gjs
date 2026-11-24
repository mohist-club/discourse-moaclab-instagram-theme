import IgStudiosPage from "../../components/ig-studios-page";

const IgStudiosPageConnector = <template>
  <IgStudiosPage @categories={{@outletArgs.categories}} />
</template>;

export default IgStudiosPageConnector;
