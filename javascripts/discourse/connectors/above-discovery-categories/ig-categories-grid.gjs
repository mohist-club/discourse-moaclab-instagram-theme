import IgCategoriesGrid from "../../components/ig-categories-grid";

const IgCategoriesGridConnector = <template>
  <IgCategoriesGrid @categories={{@outletArgs.categories}} />
</template>;

export default IgCategoriesGridConnector;
