public with sharing class ShopifyDraftOrderHandler {
    
    public class Customer {
        public Long id { get; set; }
        public String first_name { get; set; }
        public String last_name { get; set; }
        public String email { get; set; }
        public String phone { get; set; }
        
        public Customer(String firstName, String lastName, String email, String phone) {
            this.first_name = firstName;
            this.last_name = lastName;
            this.email = email;
            this.phone = phone;
        }
    }    
    
    public class LineItem {
        public String title { get; set; }
        public Integer quantity { get; set; }
        public Decimal price { get; set; }
        public String sku { get; set; }
        
        public LineItem(String title, Integer quantity, Decimal price, String sku) {
            this.title = title;
            this.quantity = quantity;
            this.price = price;
            this.sku = sku;
        }
    }
    
    public class DraftOrder {
        public Long id { get; set; }
        public Long customer_id { get; set; }
        public List<LineItem> line_items { get; set; }
        
        public DraftOrder(Long customerId, List<LineItem> lineItems) {
            this.customer_id = customerId;
            this.line_items = lineItems;
        }
        
        private Decimal calculateTotalPrice(List<LineItem> lineItems) {
            Decimal total = 0;
            for (LineItem item : lineItems) {
                total += item.price * item.quantity;
            }
            return total;
        }
    }
    
    public class CustomerResponse {
        public Customer customer { get; set; }
    }    
    
    public class DraftOrderResponse {
        public DraftOrder draft_order { get; set; }
    }
    
    public static Long createCustomer(String firstName, String lastName, String email, String phone) {
        Customer customer = new Customer(firstName, lastName, email, phone);
        
        String endpoint = 'callout:ShopifyNC/customers.json';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        
        // Serialize the customer object to JSON
        req.setBody(JSON.serialize(new Map<String, Customer>{'customer' => customer}));

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug(res.getStatusCode());
        
        if (res.getStatusCode() == 201) {
            CustomerResponse response = (CustomerResponse) JSON.deserialize(res.getBody(), CustomerResponse.class);
            System.debug(response);
            System.debug('Customer Created: ' + response.customer);
            return response.customer.id; // Return the created customer ID
        } else {
            System.debug('Error creating customer: ' + res.getBody());
            return null;
        }
    }    
    
    public static void createDraftOrder(String orderId) {
		//Get order record 
        Opportunity order = [SELECT ID, AccountId FROM Opportunity WHERE Id =: orderId];
        
        //Send contact data linked in order to shopify
        Account customer = [SELECT ID, FirstName, LastName, PersonEmail, ShopifyId__c, Phone FROM Account WHERE Id =: order.AccountId];
        Long shopifyCustomerId = createCustomer(customer.FirstName, customer.LastName, customer.PersonEmail, customer.Phone);
        customer.ShopifyId__c = String.valueOf(shopifyCustomerId);        
        
		if (shopifyCustomerId != null) {        
            List<OpportunityLineItem> products = new List<OpportunityLineItem>([SELECT ID, Name, Quantity, ListPrice, OpportunityId FROM OpportunityLineItem WHERE OpportunityId =: OrderId]);
            
            //Get all line items associated to the order
            List<ShopifyDraftOrderHandler.LineItem> lineItems = new List<ShopifyDraftOrderHandler.LineItem>();
            
            //Building list of line items to send to shopify
            for(OpportunityLineItem currProduct : products){
                lineItems.add(new ShopifyDraftOrderHandler.LineItem(currProduct.Name, (Integer)currProduct.Quantity, currProduct.ListPrice, currProduct.Id));
            }            

                DraftOrder draftOrder = new DraftOrder(shopifyCustomerId, lineItems);
        
                String endpoint = 'callout:ShopifyNC/draft_orders.json';
                HttpRequest req = new HttpRequest();
                req.setEndpoint(endpoint);
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                
                // Wrap the draft order in a map with the key 'draft_order' and 'customer'
                Map<String, Object> draftOrderMap = new Map<String, Object>();
                draftOrderMap.put('customer', new Map<String, Object>{ 'id' => shopifyCustomerId }); // Use 'customer' instead of 'customer_id'
                draftOrderMap.put('line_items', lineItems);
                
            	//Build and send the payload
                Map<String, Object> payload = new Map<String, Object>();
                payload.put('draft_order', draftOrderMap);               
                req.setBody(JSON.serialize(payload));
                Http http = new Http();
                HttpResponse res = http.send(req);
         		
                if (res.getStatusCode() == 201) {
                    DraftOrderResponse response = (DraftOrderResponse) JSON.deserialize(res.getBody(), DraftOrderResponse.class);
                    //System.debug(response.draft_order.id);
                    order.ShopifyDraftOrderId__c = String.valueOf(response.draft_order.id);
                    update order;
                    System.debug('Draft Order Created: ' + response.draft_order);
                } else {
                    System.debug('Error creating draft order: ' + res.getBody());
                }            	
        }
    }
}